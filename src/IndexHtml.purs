module IndexHtml where

import Data.Foldable (foldr)
import Prelude hiding (id)
import Control.Lens ((~))
import Data.Tuple
import Data.String (replace)
import Text.Smolder.HTML
  (html, head, meta, script, style, body, div, h1, canvas, title, link, p)
import Text.Smolder.HTML.Attributes
  (lang, charset, httpEquiv, content, src, defer, type', id, name, rel, href)
import Text.Smolder.Markup (text, (!), Markup())
import Text.Smolder.Renderer.String (render)

import Utils ((>>), fmap)
import Style

replaceAll :: [Tuple String String] -> String -> String
replaceAll = fmap (uncurry replace) >>> foldr (>>>) Prelude.id

styles =
  replaceAll
    [ "$backgroundColor" ~ backgroundColor
    , "$fontColor" ~ fontColor
    , "$fontName" ~ fontName
    , "$canvasSize" ~ (show canvasSize)
    ] $ """
  #background {
    position: absolute;
    z-index: 0;
  }

  #foreground {
    position: absolute;
    z-index: 1;
  }

  body {
    background-color: $backgroundColor;
    color: $fontColor;
    font-family: $fontName, sans-serif;
  }

  h1 {
    text-align: center;
  }

  #game {
    margin: 0 auto;
    width: $canvasSizepx;
  }
  """

indexDoc =
  html ! lang "en" $ do
    head $ do
      meta ! charset "utf-8"
      meta ! httpEquiv "X-UA-Compatible" ! content "IE=edge,chrome=1"
      script ! src "/js/game.js" ! defer "" $ text ""
      link ! rel "stylesheet" ! type' "text/css" ! href fontUrl
      style ! type' "text/css" $ text styles
     
    body $ do
      div ! id "game" $ do
        h1 $ text "multipac"
        canvas ! id "foreground" $ text ""
        canvas ! id "background" $ text ""

indexHtml = render indexDoc
