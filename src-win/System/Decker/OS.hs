{-- Author: Jan-Philipp Stauffert <jan-philipp.stauffert@uni-wuerzburg.de.de> --}
module System.Decker.OS
  ( defaultProvisioning
  , urlPath
  , preextractedResourceFolder
  , chrome
  ) where

import Common
import Data.List
import System.Environment
import System.FilePath

defaultProvisioning :: Provisioning
defaultProvisioning = Copy

urlPath :: FilePath -> FilePath
urlPath path = intercalate "/" (splitDirectories path)

preextractedResourceFolder :: IO FilePath
preextractedResourceFolder = do
  exep <- getExecutablePath
  return $ joinPath [(takeDirectory exep), "..", "resource"]

chrome :: IO String
chrome = return "start chrome"
