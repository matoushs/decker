{-- Author: Henrik Tramberend <henrik@tramberend.de> --}
module Text.Decker.Writer.Html
  ( writeIndexLists
  , markdownToHtmlDeck
  , markdownToHtmlHandout
  , markdownToHtmlPage
  , toPandocMeta
  , DeckerException(..)
  ) where

import Text.Decker.Filter.Filter
import Text.Decker.Internal.Common
import Text.Decker.Internal.Exception
import Text.Decker.Internal.Meta
import Text.Decker.Project.Project
import Text.Decker.Project.Shake
import Text.Decker.Reader.Markdown
import Text.Pandoc.Lens

import Control.Lens ((^.))
import Control.Monad.State
import qualified Data.Map as M
import qualified Data.MultiMap as MM
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Development.Shake
import Development.Shake.FilePath as SFP
import Text.DocTemplates
import Text.Pandoc hiding (getTemplate)
import Text.Pandoc.Highlighting
import Text.Printf

-- | Generates an index.md file with links to all generated files of interest.
writeIndexLists :: FilePath -> FilePath -> Action ()
writeIndexLists out baseUrl = do
  dirs <- projectDirsA
  ts <- targetsA
  let projectDir = dirs ^. project
  let decks = zip (_decks ts) (_decksPdf ts)
  let handouts = zip (_handouts ts) (_handoutsPdf ts)
  let pages = zip (_pages ts) (_pagesPdf ts)
  decksLinks <- makeGroupedLinks projectDir decks
  handoutsLinks <- makeGroupedLinks projectDir handouts
  pagesLinks <- makeGroupedLinks projectDir pages
  liftIO $
    writeFile out $
    unlines
      [ "---"
      , "title: Generated Index"
      , "subtitle: " ++ projectDir
      , "---"
      , "# Slide decks"
      , unlines decksLinks
      , "# Handouts"
      , unlines handoutsLinks
      , "# Supporting Documents"
      , unlines pagesLinks
      ]
  where
    makeLink (html, pdf) = do
      pdfExists <- doesFileExist pdf
      if pdfExists
        then return $
             printf
               "-    [%s <i class='fab fa-html5'></i>](%s) [<i class='fas fa-file-pdf'></i>](%s)"
               (takeFileName html)
               (makeRelative baseUrl html)
               (makeRelative baseUrl pdf)
        else return $
             printf
               "-    [%s <i class='fab fa-html5'></i>](%s)"
               (takeFileName html)
               (makeRelative baseUrl html)
    makeGroupedLinks :: FilePath -> [(FilePath, FilePath)] -> Action [String]
    makeGroupedLinks project files =
      let grouped = MM.fromList (zip (map (takeDirectory . fst) files) files)
          renderGroup :: FilePath -> Action [String]
          renderGroup key =
            (printf "\n## %s:" (makeRelative project key) :) <$>
            mapM makeLink (MM.lookup key grouped)
       in concat <$> mapM renderGroup (MM.keys grouped)

-- | Write Pandoc in native format right next to the output file
writeNativeWhileDebugging :: FilePath -> String -> Pandoc -> Action ()
writeNativeWhileDebugging out mod doc =
  liftIO $
  runIO (writeNative pandocWriterOpts doc) >>= handleError >>=
  T.writeFile (out -<.> mod <.> ".hs")

-- | Write a markdown file to a HTML file using the page template.
markdownToHtmlDeck :: FilePath -> FilePath -> FilePath -> Action ()
markdownToHtmlDeck markdownFile out index = do
  putCurrentDocument out
  supportDir <- getRelativeSupportDir (takeDirectory out)
  let disp = Disposition Deck Html
  pandoc@(Pandoc meta _) <- readAndProcessMarkdown markdownFile disp
  let highlightStyle =
        case getMetaString "highlightjs" meta of
          Nothing -> Just pygments
          _ -> Nothing
  template <- getTemplate disp
  dachdeckerUrl' <- liftIO getDachdeckerUrl
  let options =
        pandocWriterOpts
          { writerSlideLevel = Just 1
          , writerTemplate = Just template
          , writerHighlightStyle = highlightStyle
          , writerHTMLMathMethod =
              MathJax "Handled by reveal.js in the template"
          , writerVariables =
              Context $
              M.fromList
                [ ("decker-support-dir", SimpleVal $ Text 0 $ T.pack supportDir)
                , ("dachdecker-url", SimpleVal $ Text 0 $ T.pack dachdeckerUrl')
                ]
          , writerCiteMethod = Citeproc
          }
  writePandocFile "revealjs" options out pandoc
  when (getMetaBoolOrElse "write-notebook" False meta) $
    markdownToNotebook markdownFile (out -<.> ".ipynb")
  writeNativeWhileDebugging out "filtered" pandoc

writePandocFile :: T.Text -> WriterOptions -> FilePath -> Pandoc -> Action ()
writePandocFile fmt options out pandoc =
  liftIO $
  runIO (writeRevealJs options pandoc) >>= handleError >>= T.writeFile out

-- | Write a markdown file to a HTML file using the page template.
markdownToHtmlPage :: FilePath -> FilePath -> Action ()
markdownToHtmlPage markdownFile out = do
  putCurrentDocument out
  supportDir <- getRelativeSupportDir (takeDirectory out)
  let disp = Disposition Page Html
  pandoc@(Pandoc docMeta _) <- readAndProcessMarkdown markdownFile disp
  template <- getTemplate disp
  let options =
        pandocWriterOpts
          { writerTemplate = Just template
          , writerHighlightStyle = Just pygments
          , writerHTMLMathMethod =
              MathJax "Handled by reveal.js in the template"
          , writerVariables =
              Context $
              M.fromList
                [("decker-support-dir", SimpleVal $ Text 0 $ T.pack supportDir)]
          , writerCiteMethod = Citeproc
          , writerTableOfContents = getMetaBoolOrElse "show-toc" False docMeta
          , writerTOCDepth = getMetaIntOrElse "toc-depth" 1 docMeta
          }
  writePandocFile "html5" options out pandoc

-- | Write a markdown file to a HTML file using the handout template.
markdownToHtmlHandout :: FilePath -> FilePath -> Action ()
markdownToHtmlHandout markdownFile out = do
  putCurrentDocument out
  supportDir <- getRelativeSupportDir (takeDirectory out)
  let disp = Disposition Handout Html
  pandoc@(Pandoc docMeta _) <-
    wrapSlidesinDivs <$> readAndProcessMarkdown markdownFile disp
  template <- getTemplate disp
  let options =
        pandocWriterOpts
          { writerTemplate = Just template
          , writerHighlightStyle = Just pygments
          , writerHTMLMathMethod =
              MathJax "Handled by reveal.js in the template"
          , writerVariables =
              Context $
              M.fromList
                [("decker-support-dir", SimpleVal $ Text 0 $ T.pack supportDir)]
          , writerCiteMethod = Citeproc
          , writerTableOfContents = getMetaBoolOrElse "show-toc" False docMeta
          , writerTOCDepth = getMetaIntOrElse "toc-depth" 1 docMeta
          }
  writePandocFile "html5" options out pandoc

-- | Write a markdown file to a HTML file using the page template.
markdownToNotebook :: FilePath -> FilePath -> Action ()
markdownToNotebook markdownFile out = do
  putCurrentDocument out
  supportDir <- getRelativeSupportDir (takeDirectory out)
  let disp = Disposition Notebook Html
  pandoc@(Pandoc docMeta _) <-
    filterNotebookSlides <$> readAndProcessMarkdown markdownFile disp
  let options =
        pandocWriterOpts
          { writerTemplate = Nothing
          , writerHighlightStyle = Just pygments
          , writerVariables =
              Context $
              M.fromList
                [("decker-support-dir", SimpleVal $ Text 0 $ T.pack supportDir)]
          }
  writePandocFile "ipynb" options out pandoc
