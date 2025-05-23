{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}
{-
Copyright (C) 2009 John MacFarlane <jgm@berkeley.edu>
This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
-}

{- | Functions for initializing a Gitit wiki.
-}

module Network.Gitit.Initialize ( initializeGititState
                                , recompilePageTemplate
                                , compilePageTemplate
                                , createStaticIfMissing
                                , createRepoIfMissing
                                , createDefaultPages
                                , createTemplateIfMissing )
where
import System.FilePath ((</>), (<.>))
import Data.Semigroup ((<>))
import Data.Text (Text)
import qualified Data.Text as T
import Data.FileStore
import qualified Data.Map as M
import Network.Gitit.Util (readFileUTF8)
import Network.Gitit.Types
import Network.Gitit.State
import Network.Gitit.Framework
import Network.Gitit.Plugins
import Network.Gitit.Layout (defaultRenderPage)
import Network.Gitit.MetaInformation (getDataFileName)
import Control.Exception (throwIO, try)
import System.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, doesFileExist)
import Control.Monad ((<=<), unless, forM_, liftM)
import Text.Pandoc hiding (getDataFileName, WARNING)
import System.Log.Logger (logM, Priority(..))
import qualified Text.StringTemplate as ST


-- | Initialize Gitit State.
initializeGititState :: Config -> IO ()
initializeGititState conf = do
  let userFile' = userFile conf
      pluginModules' = pluginModules conf
  plugins' <- loadPlugins pluginModules'

  userFileExists <- doesFileExist userFile'
  users' <- if userFileExists
               then liftM (M.fromList . read . T.unpack) $ readFileUTF8 userFile'
               else return M.empty

  templ <- compilePageTemplate (templatesDir conf)

  updateGititState $ \s -> s { sessions      = Sessions M.empty
                             , users         = users'
                             , renderPage    = defaultRenderPage templ
                             , plugins       = plugins' }

-- | Recompile the page template.
recompilePageTemplate :: Config -> IO ()
recompilePageTemplate cfg = do
  ct <- compilePageTemplate (templatesDir cfg)
  updateGititState $ \st -> st{renderPage = defaultRenderPage ct}

--- | Compile a master page template named @page.st@ in the directory specified.
compilePageTemplate :: FilePath -> IO (ST.StringTemplate String)
compilePageTemplate tempsDir = do
  defaultGroup <- getDataFileName ("data" </> "templates") >>= ST.directoryGroup
  customExists <- doesDirectoryExist tempsDir
  combinedGroup <-
    if customExists
       -- default templates from data directory will be "shadowed"
       -- by templates from the user's template dir
       then do customGroup <- ST.directoryGroup tempsDir
               return $ ST.mergeSTGroups customGroup defaultGroup
       else do logM "gitit" WARNING $ "Custom template directory not found"
               return defaultGroup
  case ST.getStringTemplate "page" combinedGroup of
        Just t    -> return t
        Nothing   -> error "Could not get string template"

-- | Create templates dir if it doesn't exist.
createTemplateIfMissing :: Config -> IO ()
createTemplateIfMissing conf' = do
  templateExists <- doesDirectoryExist (templatesDir conf')
  unless templateExists $ do
    createDirectoryIfMissing True (templatesDir conf')
    templatePath <- getDataFileName $ "data" </> "templates"
    -- templs <- liftM (filter (`notElem` [".",".."])) $
    --  getDirectoryContents templatePath
    -- Copy footer.st, since this is the component users
    -- are most likely to want to customize:
    forM_ ["footer.st"] $ \t -> do
      copyFile (templatePath </> t) (templatesDir conf' </> t)
      logM "gitit" WARNING $ "Created " ++ (templatesDir conf' </> t)

-- | Create page repository unless it exists.
createRepoIfMissing :: Config -> IO ()
createRepoIfMissing conf = do
  let fs = filestoreFromConfig conf
  repoExists <- try (initialize fs) >>= \res ->
    case res of
         Right _               -> do
           logM "gitit" WARNING $ "Created repository in " ++ repositoryPath conf
           return False
         Left RepositoryExists -> return True
         Left e                -> throwIO e >> return False
  unless repoExists $ createDefaultPages conf

createDefaultPages :: Config -> IO ()
createDefaultPages conf = do
    let fs = filestoreFromConfig conf
        pt = defaultPageType conf
        toPandoc = readMarkdown def{ readerExtensions = enableExtension Ext_smart (readerExtensions def) }
        defOpts = def{ writerExtensions = if showLHSBirdTracks conf
                                             then enableExtension
                                                  Ext_literate_haskell
                                                  $ writerExtensions def
                                             else writerExtensions def
                     }
        -- note: we convert this (markdown) to the default page format
        converter = handleError . runPure . case pt of
                       Markdown   -> return
                       LaTeX      -> writeLaTeX defOpts <=< toPandoc
                       HTML       -> writeHtml5String defOpts <=< toPandoc
                       RST        -> writeRST defOpts <=< toPandoc
                       Textile    -> writeTextile defOpts <=< toPandoc
                       Org        -> writeOrg defOpts <=< toPandoc
#if MIN_VERSION_pandoc(3,0,0)
                       DocBook    -> writeDocBook5 defOpts <=< toPandoc
#else
                       DocBook    -> writeDocbook5 defOpts <=< toPandoc
#endif
                       MediaWiki  -> writeMediaWiki defOpts <=< toPandoc
                       CommonMark -> writeCommonMark defOpts <=< toPandoc

    welcomepath <- getDataFileName $ "data" </> "FrontPage" <.> "page"
    welcomecontents <- converter =<< readFileUTF8 welcomepath
    helppath <- getDataFileName $ "data" </> "Help" <.> "page"
    helpcontentsInitial <- converter =<< readFileUTF8 helppath
    markuppath <- getDataFileName $ "data" </> "markup" <.> show pt
    helpcontentsMarkup <- converter =<< readFileUTF8 markuppath
    let helpcontents = helpcontentsInitial <> "\n\n" <> helpcontentsMarkup
    usersguidepath <- getDataFileName "README.markdown"
    usersguidecontents <- converter =<< readFileUTF8 usersguidepath
    -- include header in case user changes default format:
    let header = "---\nformat: " <>
          T.pack (show pt) <> (if defaultLHS conf then "+lhs" else "") <>
          "\n...\n\n"
    -- add front page, help page, and user's guide
    let auth = Author "Gitit" ""
    createIfMissing fs (frontPage conf <.> defaultExtension conf) auth "Default front page"
      $ header <> welcomecontents
    createIfMissing fs ("Help" <.> defaultExtension conf) auth "Default help page"
      $ header <> helpcontents
    createIfMissing fs ("Gitit User’s Guide" <.> defaultExtension conf) auth "User’s guide (README)"
      $ header <> usersguidecontents

createIfMissing :: FileStore -> FilePath -> Author -> Description -> Text -> IO ()
createIfMissing fs p a comm cont = do
  res <- try $ create fs p a comm (T.unpack cont)
  case res of
       Right _ -> logM "gitit" WARNING ("Added " ++ p ++ " to repository")
       Left ResourceExists -> return ()
       Left e              -> throwIO e >> return ()

-- | Create static directory unless it exists.
createStaticIfMissing :: Config -> IO ()
createStaticIfMissing conf = do
  let staticdir = staticDir conf
  staticExists <- doesDirectoryExist staticdir
  unless staticExists $ do

    let cssdir = staticdir </> "css"
    createDirectoryIfMissing True cssdir
    cssDataDir <- getDataFileName $ "data" </> "static" </> "css"
    -- cssFiles <- liftM (filter (\f -> takeExtension f == ".css")) $ getDirectoryContents cssDataDir
    forM_ ["custom.css"] $ \f -> do
      copyFile (cssDataDir </> f) (cssdir </> f)
      logM "gitit" WARNING $ "Created " ++ (cssdir </> f)

    {-
    let icondir = staticdir </> "img" </> "icons"
    createDirectoryIfMissing True icondir
    iconDataDir <- getDataFileName $ "data" </> "static" </> "img" </> "icons"
    iconFiles <- liftM (filter (\f -> takeExtension f == ".png")) $ getDirectoryContents iconDataDir
    forM_ iconFiles $ \f -> do
      copyFile (iconDataDir </> f) (icondir </> f)
      logM "gitit" WARNING $ "Created " ++ (icondir </> f)
    -}

    logopath <- getDataFileName $ "data" </> "static" </> "img" </> "logo.png"
    createDirectoryIfMissing True $ staticdir </> "img"
    copyFile logopath $ staticdir </> "img" </> "logo.png"
    logM "gitit" WARNING $ "Created " ++ (staticdir </> "img" </> "logo.png")

    {-
    let jsdir = staticdir </> "js"
    createDirectoryIfMissing True jsdir
    jsDataDir <- getDataFileName $ "data" </> "static" </> "js"
    javascripts <- liftM (filter (`notElem` [".", ".."])) $ getDirectoryContents jsDataDir
    forM_ javascripts $ \f -> do
      copyFile (jsDataDir </> f) (jsdir </> f)
      logM "gitit" WARNING $ "Created " ++ (jsdir </> f)
    -}

