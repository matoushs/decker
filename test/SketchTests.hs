module SketchTests
  ( sketchTests
  ) where

import Sketch
import Slide
import Test.Hspec
import Text.Pandoc
import Text.Pandoc.Lens

import Control.Lens

noIdSlide = Slide (Just $ Header 1 ("", [], []) []) []

someIdSlide = Slide (Just $ Header 1 ("manually-set-id", [], []) []) []

noHeaderSlide = Slide Nothing []

sketchTests = do
  describe "randomId" $ do
    it "creates a random id" $ length <$> randomId `shouldReturn` idDigits + 1
    it "creates a random id that starts with 's'" $
      head <$> randomId `shouldReturn` 's'
  describe "provideSlideIdIO" $ do
    it "adds new id to any slide that does not have one" $
      length . view (header . _Just . attributes . attrIdentifier) <$>
      provideSlideIdIO noIdSlide `shouldReturn` idDigits + 1
    it "adds new header and id to any slide that does not have either" $
      length . view (header . _Just . attributes . attrIdentifier) <$>
      provideSlideIdIO noHeaderSlide `shouldReturn` idDigits + 1
    it "does not touch headers that already have an id" $
      view (header . _Just . attributes . attrIdentifier) <$>
      provideSlideIdIO someIdSlide `shouldReturn` "manually-set-id"
