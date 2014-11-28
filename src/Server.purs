module Server where

import Debug.Trace
import Data.Tuple
import Data.JSON
import Data.Function
import Data.Maybe
import Data.Array
import qualified Data.Either as E
import qualified Data.Map as M
import Data.Foldable (for_)
import Control.Monad
import Control.Monad.Eff
import Control.Monad.Eff.Ref
import Control.Reactive.Timer

import qualified NodeWebSocket as WS
import qualified NodeHttp as Http
import Types
import Game
import Utils

initialState :: ServerState
initialState =
  { game: initialGame
  , input: M.empty
  , connections: []
  }

stepsPerSecond = 30

main = do
  refState <- newRef initialState

  chdir "static"
  port <- portOrDefault 8080

  httpServer <- createHttpServer
  wsServer <- createWebSocketServer refState

  WS.mount wsServer httpServer
  Http.listen httpServer port
  trace $ "listening on " <> show port <> "..."

  startMainLoop refState


createHttpServer =
  Http.createServer $ \req res -> do
    let path = (Http.getUrl req).pathname
    let reply =
      case path of
          "/"           -> Http.sendFile "index.html"
          "/js/game.js" -> Http.sendFile "js/game.js"
          _             -> Http.send404
    reply res


createWebSocketServer refState = do
  server <- WS.mkServer
  WS.onRequest server $ \req -> do
    trace "got a request"
    conn <- WS.accept req

    maybePId <- addPlayer conn refState "harry"

    case maybePId of
      Just pId -> do
        trace $ "opened connection for player " <> show pId
        WS.onMessage conn (handleMessage refState pId)
        WS.onClose   conn (handleClose refState pId)
      Nothing -> do
        trace "rejecting connection, no player ids available"
        WS.close conn

  return server


startMainLoop refState =
  void $ interval (1000 / stepsPerSecond) $ do
    s <- readRef refState

    let result = stepGame s.input s.game
    let game' = fst result
    let updates = snd result

    let s' = s { game = game', input = M.empty }
    writeRef refState s'

    sendUpdates refState updates


addPlayer conn refState name = do
  state <- readRef refState
  case getNextPlayerId state of
    Just pId -> do
      let state' = state { connections =
                            state.connections <>
                              [{ pId: pId, wsConn: conn, name: name }] }
      writeRef refState state'
      return (Just pId)
    Nothing ->
      return Nothing


getNextPlayerId :: ServerState -> Maybe PlayerId
getNextPlayerId state =
  let playerIdsInUse = map (\c -> c.pId) state.connections
  in  head $ allPlayerIds \\ playerIdsInUse


handleMessage :: forall e.
  RefVal ServerState
  -> PlayerId
  -> WS.Message
  -> Eff (trace :: Trace, ws :: WS.WebSocket, ref :: Ref | e) Unit
handleMessage refState pId msg = do
  case eitherDecode msg of
    E.Right newDir ->
      modifyRef refState $ \s ->
        let newInput = M.insert pId (Just newDir) s.input
        in  s { input = newInput }
    E.Left err ->
      trace err


handleClose :: forall e.
  RefVal ServerState
  -> PlayerId
  -> WS.Close
  -> Eff (ws :: WS.WebSocket, trace :: Trace, ref :: Ref | e) Unit
handleClose refState pId _ = do
  state <- readRef refState
  let conns = filter (\c -> pId /= c.pId) state.connections
  let state' = state { connections = conns }
  writeRef refState state'
  trace $ "closed connection for player " <> show pId


sendUpdates :: forall e.
  RefVal ServerState
  -> [GameUpdate]
  -> Eff (ref :: Ref, ws :: WS.WebSocket | e) Unit
sendUpdates refState updates = do
  state <- readRef refState
  for_ updates $ \update ->
    for_ state.connections $ \c ->
      sendUpdate c.wsConn update

sendUpdate :: forall e.
  WS.Connection -> GameUpdate -> Eff (ws :: WS.WebSocket | e) Unit
sendUpdate conn update =
  when (shouldBroadcast update) $
    WS.send conn $ encode update

shouldBroadcast :: GameUpdate -> Boolean
shouldBroadcast (GUPU _ (ChangedPosition _)) = true
shouldBroadcast _ = false


foreign import data Process :: !

foreign import chdir
  """
  function chdir(path) {
    return function() {
      process.chdir(path)
    }
  }
  """ :: forall e. String -> Eff (process :: Process | e) Unit

foreign import getEnvImpl
  """
  function getEnvImpl(just, nothing, key) {
    return function() {
      var v = process.env[key]
      return v ? just(v) : nothing
    }
  }
  """ :: forall e a.
  Fn3
    (a -> Maybe a)
    (Maybe a)
    String
    (Eff (process :: Process | e) (Maybe String))

getEnv :: forall e.
  String -> Eff (process :: Process | e) (Maybe String)
getEnv key =
  runFn3 getEnvImpl Just Nothing key

parseNumber :: String -> Maybe Number
parseNumber = decode

portOrDefault :: forall e.
  Number -> Eff (process :: Process | e) Number
portOrDefault default = do
  port <- getEnv "PORT"
  return $ fromMaybe default (port >>= parseNumber)
