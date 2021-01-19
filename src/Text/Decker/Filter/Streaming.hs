{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE TupleSections #-}

module Text.Decker.Filter.Streaming where

import Control.Monad.Catch

import qualified Data.Text as Text

import Relude

import Text.Blaze.Html
import qualified Text.Blaze.Html5 as H
import qualified Text.Blaze.Html5.Attributes as A
import Text.Decker.Filter.Attrib
import Text.Decker.Filter.Local
import Text.Decker.Filter.Macro
import Text.Decker.Internal.Exception
import Text.Decker.Internal.URI
import Text.Pandoc
import Text.Printf
import Text.URI (URI)
import qualified Text.URI as URI
import qualified Data.List as List

justToList :: [Maybe a] -> [a]
justToList = reverse . justToList'
  where
    justToList' ((Just x):xs) = x : justToList xs
    justToList' _ = []

youtubeDefaults =
  [ ("cc_load_policy", "0")
  , ("controls", "2")
  , ("iv_load_policy", "3")
  , ("modestbranding", "1")
  , ("rel", "0")
  , ("showinfo", "0")
  ]

-- https://developers.google.com/youtube/player_parameters?hl=de#IFrame_Player_API
youtubeParams =
  [ "cc_load_policy"
  , "color"
  -- , "autoplay" is handled by reveal.js
  , "controls"
  , "disablekb"
  , "enablejsapi"
  , "end"
  , "fs"
  , "hl"
  , "iv_load_policy"
  , "loop"
  , "modestbranding"
  , "origin"
  , "playsinline"
  , "playlist"
  , "rel"
  , "showinfo"
  , "start"
  ]

youtubeFlags =
  [ "cc_load_policy"
  , "disablekb"
  -- , "autoplay" is handled by reveal.js
  , "controls"
  , "enablejsapi"
  , "fs"
  , "loop"
  , "modestbranding"
  , "playsinline"
  , "rel"
  , "showinfo"
  ]

-- https://dev.twitch.tv/docs/embed/video-and-clips/
twitchDefaults = [("parent", "localhost"),("allowfullscreen","true")]

-- https://vimeo.zendesk.com/hc/en-us/articles/360001494447-Using-Player-Parameters
vimeoDefaults =
  [ ("byline", "0")
  , ("controls", "1")
  , ("dnt", "1")
  , ("fun", "0")
  , ("title", "0")
  , ("transparent", "false")
  ]

vimeoParams =
  [ "autopause"
  -- , "autoplay" is handled by reveal.js
  , "background"
  , "byline"
  , "color"
  , "controls"
  , "dnt"
  , "fun"
  , "loop"
  , "muted"
  , "playsinline"
  , "portrait"
  , "quality"
  , "speed"
  , "textrack"
  , "title"
  , "transparent"
  ]

vimeoFlags =
  [ "autopause"
  -- , "autoplay" is handled by reveal.js
  , "background"
  , "byline"
  , "controls"
  , "dnt"
  , "fun"
  , "loop"
  , "muted"
  , "playsinline"
  , "portrait"
  , "speed"
  , "title"
  , "transparent"
  ]

-- TODO this is just an adapter for the old stuff
streamHtml :: URI -> [Inline] -> Attrib Html
streamHtml uri caption = do
  let scheme = uriScheme uri
  width <- srcAttribute "width"
  height <- srcAttribute "height"
  let args = maybe [] (\w -> maybe [w] (\h -> [w, h]) height) width
  attr <- src
  streamId <-
    case URI.uriAuthority uri of
      Right (URI.Authority _ host _) -> pure $ URI.unRText host
      _ -> return $ uriPath uri
  return $
    toHtml $ embedWebVideosHtml (fromMaybe "" scheme) args attr (streamId, "")

streamHtml' :: URI -> [Inline] -> Attrib Html
streamHtml' uri caption = do
  let scheme = uriScheme uri
  let streamId = uriPath uri
  streamUri <-
    case scheme of
      Just "youtube" -> mkYoutubeUri streamId
      Just "vimeo" -> mkVimeoUri streamId
      Just "twitch" -> mkTwitchUri streamId
      _ ->
        throwM $
        ResourceException $
        "Unsupported stream service: " <> toString (fromMaybe "<none>" scheme)
  iframeAttr <- takeIframeAttr >> takeAutoplay >> extractAttr
  wrapperAttr <- takeWrapperAttr >> extractAttr
  let streamTag = mkStreamTag streamUri wrapperAttr iframeAttr
  case caption of
    [] -> do
      divAttr <-
        injectClass "nofigure" >> injectBorder >> takeSize >> takeUsual >>
        extractAttr
      return $ mkDivTag streamTag divAttr
    caption -> do
      figAttr <- injectBorder >> takeSize >> takeUsual >> extractAttr
      captionHtml <- lift $ inlinesToHtml caption
      return $ mkFigureTag streamTag captionHtml figAttr

takeWrapperAttr :: Attrib ()
takeWrapperAttr = do
  aspect <- calcAspect . fromMaybe "" <$> cutAttrib "aspect"
  injectStyle ("position", "relative")
  injectStyle ("padding-top", "25px")
  injectStyle ("padding-bottom", aspect)
  injectStyle ("height", "0")

takeIframeAttr :: Attrib ()
takeIframeAttr = do
  injectStyle ("position", "absolute")
  injectStyle ("top", "0")
  injectStyle ("left", "0")
  injectStyle ("width", "100%")
  injectStyle ("height", "100%")
  injectAttribute ("allow", "fullscreen")
  takeAutoplay

mkYoutubeUri :: Text -> Attrib URI
mkYoutubeUri streamId = do
  flags <- cutClasses youtubeFlags
  params <- enableLoop flags <$> cutAttribs youtubeParams
  uri <- URI.mkURI $ "https://www.youtube.com/embed/" <> streamId
  setQuery [] (merge [params, map (, "1") flags, youtubeDefaults]) uri
  where
    enableLoop flags params =
      if "loop" `elem` flags
        then ("playlist", streamId) : params
        else params

mkVimeoUri :: Text -> Attrib URI
mkVimeoUri streamId = do
  params <- cutAttribs vimeoParams
  flags <- cutClasses vimeoFlags
  uri <- URI.mkURI $ "https://player.vimeo.com/video/" <> streamId
  setQuery [] (merge [params, map (, "1") flags, vimeoDefaults]) uri

-- Twitch supports autoplay, muted and time (time is translated from start)
-- Twitch needs autoplay="false" in URI or the video will autoplay
mkTwitchUri :: Text -> Attrib URI
mkTwitchUri streamId = do
  uri <- URI.mkURI "https://player.twitch.tv/"
  (_, (_, flags, params)) <- get   
  setQuery [] ([("video", streamId)] ++ twitchDefaults ++ hasAutoplay flags ++ hasStart params) uri
  where  
    hasAutoplay (f:fx) = 
      case f of 
        "autoplay" -> map (, "true") fx
        "muted" -> ("muted", "true") : hasAutoplay fx
        _ -> hasAutoplay fx
    hasAutoplay [] = [("autoplay", "false")]
    hasStart ((p,y):ps) =
      case p of 
        "start" -> [("time", y)]
        _ -> hasStart ps
    hasStart [] = []  

calcAspect :: Text -> Text
calcAspect ratio =
  fromMaybe "56.25%" $
  case Text.splitOn ":" ratio of
    [w, h] -> do
      wf <- readMaybe $ toString w :: Maybe Float
      hf <- readMaybe $ toString h :: Maybe Float
      return $ Text.pack (printf "%.2f%%" (hf / wf * 100.0))
    _ -> Nothing

mkAttrTag :: Html -> Attr -> Html
mkAttrTag tag (id, cs, kvs) =
  tag !? (not (Text.null id), A.id (H.toValue id)) !?
  (not (null cs), A.class_ (H.toValue ("decker" : cs))) !*
  kvs

mkMediaTag :: Html -> URI -> Attr -> Html
mkMediaTag tag uri attr =
   mkAttrTag tag attr ! H.dataAttribute "src" (H.preEscapedToValue $ URI.render uri)

mkStreamTag :: URI -> Attr -> Attr -> Html
mkStreamTag uri wrapperAttr iframeAttr =
  let inner =
        mkMediaTag (H.iframe "") uri iframeAttr
   in mkAttrTag (H.div inner) wrapperAttr

mkDivTag :: Html -> Attr -> Html
mkDivTag content (id, cs, kvs) =
  H.div !? (not (Text.null id), A.id (H.toValue id)) !
  A.class_ (H.toValue ("decker" : cs)) !*
  kvs $
  content
