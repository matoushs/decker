{-- Author: Henrik Tramberend <henrik@tramberend.de> --}
module Macro
  ( expandDeckerMacros
  ) where

import Common
import Control.Monad.State
import Data.List.Split
import qualified Data.Map as Map (Map, fromList, lookup)
import Data.Maybe
import Text.Blaze (customAttribute)
import Text.Blaze.Html.Renderer.String
import Text.Blaze.Html5 as H
       ((!), div, figure, iframe, iframe, p, toValue)
import Text.Blaze.Html5.Attributes as A
       (class_, height, src, style, width)
import Text.Pandoc
import Text.Pandoc.Definition ()
import Text.Pandoc.Shared
import Text.Pandoc.Walk
import Text.Printf
import Text.Read

type MacroAction = [String] -> Attr -> Target -> Meta -> Decker Inline

-- iframe resizing, see:
-- https://css-tricks.com/NetMag/FluidWidthVideo/Article-FluidWidthVideo.php
-- YouTube links: iv_load_policy=3 disables annotations, rel=0 disables related
-- videos. See:
-- https://developers.google.com/youtube/player_parameters?hl=de#IFrame_Player_API
embedYoutubeHtml :: [String] -> Attr -> Target -> Inline
embedYoutubeHtml args attr (vid, _) =
  RawInline (Format "html") (renderHtml html)
  where
    url =
      printf
        "https://www.youtube.com/embed/%s?iv_load_policy=3&disablekb=1&rel=0&modestbranding=1&autohide=1"
        vid :: String
    vidWidthStr = macroArg 0 args "560"
    vidHeightStr = macroArg 1 args "315"
    vidWidth = readDefault 560.0 vidWidthStr :: Float
    vidHeight = readDefault 315.0 vidHeightStr :: Float
    wrapperStyle =
      printf
        "position:relative;padding-top:25px;padding-bottom:%f%%;height:0;"
        (vidHeight / vidWidth * 100.0) :: String
    iframeStyle =
      "position:absolute;top:0;left:0;width:100%;height:100%;" :: String
    figureStyle (_, _, kv) =
      foldl (\s (k, v) -> s ++ printf "%s:%s;" k v :: String) "" kv
    figureClass (_, cls, _) = unwords cls
    html =
      H.figure ! class_ (toValue (figureClass attr)) !
      style (toValue (figureStyle attr)) $
      H.div ! style (toValue wrapperStyle) $
      iframe ! style (toValue iframeStyle) ! width (toValue vidWidthStr) !
      height (toValue vidHeightStr) !
      src (toValue url) !
      customAttribute "frameborder" "0" !
      customAttribute "allowfullscreen" "" $
      H.p ""

embedYoutubePdf :: [String] -> Attr -> Target -> Inline
embedYoutubePdf _ attr (vid, _) =
  Link nullAttr [Image attr [Str text] (imageUrl, "")] (videoUrl, "")
  where
    videoUrl =
      printf
        "https://www.youtube.com/embed/%s?iv_load_policy=3&disablekb=0&rel=0&modestbranding=1&autohide=1"
        vid :: String
    imageUrl =
      printf "http://img.youtube.com/vi/%s/maxresdefault.jpg" vid :: String
    text = printf "YouTube: %s" vid :: String

youtube :: MacroAction
youtube args attr target _ = do
  disp <- gets disposition
  case disp of
    Disposition _ Html -> return $ embedYoutubeHtml args attr target
    Disposition _ Pdf -> return $ embedYoutubePdf args attr target

fontAwesome :: MacroAction
fontAwesome _ _ (iconName, _) _ = do
  disp <- gets disposition
  case disp of
    Disposition _ Html ->
      return $
      RawInline (Format "html") $ "<i class=\"fa fa-" ++ iconName ++ "\"></i>"
    Disposition _ Pdf -> return $ Str $ "[" ++ iconName ++ "]"

metaValue :: MacroAction
metaValue _ _ (key, _) meta =
  case splitOn "." key of
    [] -> return $ Str key
    k:ks -> return $ lookup' ks (lookupMeta k meta)
  where
    lookup' :: [String] -> Maybe MetaValue -> Inline
    lookup' [] (Just (MetaString s)) = Str s
    lookup' [] (Just (MetaInlines i)) = Span nullAttr i
    lookup' (k:ks) (Just (MetaMap metaMap)) = lookup' ks (Map.lookup k metaMap)
    lookup' _ _ = Strikeout [Str key]

type MacroMap = Map.Map String MacroAction

macroMap :: MacroMap
macroMap =
  Map.fromList [("meta", metaValue), ("youtube", youtube), ("fa", fontAwesome)]

readDefault :: Read a => a -> String -> a
readDefault default_ string = fromMaybe default_ (readMaybe string)

macroArg :: Int -> [String] -> String -> String
macroArg n args default_ =
  if length args > n
    then args !! n
    else default_

parseMacro :: String -> Maybe [String]
parseMacro (pre:invocation)
  | pre == ':' = Just (words invocation)
parseMacro _ = Nothing

expandInlineMacros :: Meta -> Inline -> Decker Inline
expandInlineMacros meta inline@(Link attr text target) = do
  case parseMacro $ stringify text of
    Just (name:args) -> do
      case Map.lookup name macroMap of
        Just macro -> macro args attr target meta
        Nothing -> return inline
    _ -> return inline
expandInlineMacros _ inline = return inline

expandDeckerMacros :: Pandoc -> Decker Pandoc
expandDeckerMacros doc@(Pandoc meta _) = walkM (expandInlineMacros meta) doc