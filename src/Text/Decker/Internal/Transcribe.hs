{-# LANGUAGE NoImplicitPrelude #-}

module Text.Decker.Internal.Transcribe where

import Control.Lens ((^.))
import Control.Monad
import qualified Data.Map.Strict as Map
import Development.Shake
import Development.Shake.FilePath
import Relude
import Text.Decker.Internal.Caches
import Text.Decker.Internal.Common
import Text.Decker.Internal.Helper (replaceSuffix)
import Text.Decker.Project.Project
import qualified System.Directory as Dir
import Text.Decker.Internal.Meta (lookupMetaOrElse)
import System.Process (readProcessWithExitCode)
import System.Directory (removeFile)
import Text.Decker.Filter.Local (randomId)
import Text.Pandoc (Meta)

-- | Rules for transcribiung videos. Mp4 videos are transcribed using
-- whisper.ccp if they have not yet been transcribed.
transcriptionRules :: Rules ()
transcriptionRules = do
  gpu <- newResource "GPU" 1
  (getGlobalMeta, getDeps, getTemplate) <- prepCaches
  want ["vtts"]
  phony "vtts" $ do
    meta <- getGlobalMeta
    -- language of all the recordings
    let lang = lookupMetaOrElse "de" "whisper.lang" meta
    targets <- getDeps
    -- Need vtts transcriptions for each deck that has a MP4 video transcoded (chrunched).
    forM_ (Map.keys $ targets ^. decks) $ \deck -> do
      let source = makeRelative publicDir deck
      let vtten = replaceSuffix "-deck.html" "-recording-en.vtt" deck
      let vtt = replaceSuffix "-deck.html" ("-recording-"<> lang <>".vtt") deck
      let mp4 = replaceSuffix "-deck.html" "-recording.mp4" source
      exists <- liftIO $ Dir.doesFileExist mp4
      -- translation to EN is only needed for non-EN recordings
      when exists $ need $ if lang == "en" then [vtten] else [vtten, vtt]
  -- these rules are tried in order
  alternatives $ do
    -- copies the all transcriptions to public
    publicDir <//> "*-recording-*.vtt" %> \out -> do
      let src = makeRelative publicDir out
      need [src]
      copyFileChanged src out
    -- transcribes to EN, translation is used for non-EN languages
    "**/*-recording-en.vtt" %> \out -> do
      meta <- getGlobalMeta
      let mp4 = replaceSuffix "-recording-en.vtt" "-recording.mp4" out
      need [mp4]
      let lang :: String = lookupMetaOrElse "de" "whisper.lang" meta
        -- avoid context switches on the GPU
      withResource gpu 1 $ do
        transcribe meta mp4 out (lang /= "en")
    -- transcribes to recorded language without translation.
    "**/*-recording-*.vtt" %> \out -> do
      meta <- getGlobalMeta
      let lang = lookupMetaOrElse "de" "whisper.lang" meta
      let mp4 = replaceSuffix ("-recording-" <> lang <> ".vtt") "-recording.mp4" out
      need [mp4]
        -- avoid context switches on the GPU
      withResource gpu 1 $ do
        transcribe meta mp4 out False

transcribe :: Meta -> FilePath -> String -> Bool -> Action ()
transcribe meta mp4 vtt translate = do
  let baseDir = lookupMetaOrElse "/usr/local/share/whisper.cpp" "whisper.base-dir" meta
  let model = baseDir </> lookupMetaOrElse "models/ggml-large.bin" "whisper.model" meta
  let whisper = baseDir </> "main"
  id9 <- toString <$> liftIO randomId
  let wav = transientDir </> takeFileName mp4 <> "-" <> id9 <.> "wav"
  let trans = (["--translate" | translate])
  putNormal $ "# whisper (for " <> vtt <> ")"
  putVerbose $ "ffmpeg " <> intercalate " " ["-y", "-i", mp4, "-acodec", "pcm_s16le", "-ac", "1", "-ar", "16000", wav]
  call "ffmpeg" $ ["-y", "-i", mp4, "-acodec", "pcm_s16le", "-ac", "1", "-ar", "16000", wav]
  call whisper $ ["--file", wav, "-m", model, "--language", "auto"] <> trans <> ["--output-vtt", "--output-file", dropExtension vtt]
  putVerbose $ "rm " <> wav 
  liftIO $ removeFile wav

call cmd args = do 
  (code, out, err) <- liftIO $ readProcessWithExitCode cmd args ""
  putVerbose err
  putVerbose out