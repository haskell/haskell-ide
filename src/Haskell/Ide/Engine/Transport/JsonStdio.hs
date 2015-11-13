{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE LambdaCase #-}
-- |Provide a protocol adapter/transport for JSON over stdio

module Haskell.Ide.Engine.Transport.JsonStdio where

import           Control.Applicative
import           Control.Concurrent
import           Control.Lens (view)
import           Control.Logging
import           Control.Monad.State.Strict
import qualified Data.Aeson as A
import qualified Data.Attoparsec.ByteString as AB
import qualified Data.Attoparsec.ByteString.Char8 as AB
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy as BL
import           Data.Char
import qualified Data.Map as Map
import qualified Data.Text as T
import           Haskell.Ide.Engine.PluginDescriptor
import           Haskell.Ide.Engine.Types
import qualified Pipes as P
import qualified Pipes.Aeson as PAe
import qualified Pipes.Attoparsec as PA
import qualified Pipes.ByteString as PB
import qualified Pipes.Prelude as P
import           System.IO

-- TODO: Can pass in a handle, then it is general
jsonStdioTransport :: Chan ChannelRequest -> IO ()
jsonStdioTransport cin = do
  cout <- newChan :: IO (Chan ChannelResponse)
  hSetBuffering stdout NoBuffering
  P.runEffect (parseFrames PB.stdin P.>-> parseToJsonPipe cin cout 1 P.>-> jsonConsumer)

parseToJsonPipe
  :: Chan ChannelRequest
  -> Chan ChannelResponse
  -> Int
  -> P.Pipe (Either PAe.DecodingError WireRequest) A.Value IO ()
parseToJsonPipe cin cout cid =
  do parseRes <- P.await
     case parseRes of
       Left decodeErr ->
         do let rsp =
                  CResp "" cid $
                  IdeResponseError
                    (A.toJSON (HieError (A.String $ T.pack $ show decodeErr)))
            liftIO $ debug $
              T.pack $ "jsonStdioTransport:parse error:" ++ show decodeErr
            P.yield $ A.toJSON $ channelToWire rsp
       Right req ->
         do liftIO $ writeChan cin (wireToChannel cout cid req)
            rsp <- liftIO $ readChan cout
            P.yield $ A.toJSON $ channelToWire rsp
     parseToJsonPipe cin
                     cout
                     (cid + 1)

jsonConsumer :: P.Consumer A.Value IO ()
jsonConsumer =
  do val <- P.await
     liftIO $ BL.putStr (A.encode val)
     liftIO $ BL.putStr (BL.singleton $ fromIntegral (ord '\STX'))
     jsonConsumer

parseFrames
  :: forall m
   . Monad m
  => P.Producer B.ByteString m ()
  -> P.Producer (Either PAe.DecodingError WireRequest) m ()
parseFrames prod0 = do
  -- if there are no more bytes, we just return ()
  (isEmpty, prod1) <- lift $ runStateT PB.isEndOfBytes prod0
  if isEmpty then return () else go prod1
  where
    -- ignore inputs consisting only of space
    terminatedJSON :: AB.Parser (Maybe A.Value)
    terminatedJSON = (fmap Just $ A.json' <* AB.many' AB.space <* AB.endOfInput)
                 <|> (AB.many' AB.space *> pure Nothing)
    -- endOfInput: we want to be sure that the given
    -- parser consumes the entirety of the given input
    go :: P.Producer B.ByteString m ()
       -> P.Producer (Either PAe.DecodingError WireRequest) m ()
    go prod = do
       let splitProd :: P.Producer B.ByteString m (P.Producer B.ByteString m ())
           splitProd = view (PB.break (== fromIntegral (ord '\STX'))) prod
       (maybeRet, leftoverProd) <- lift $ runStateT (PA.parse terminatedJSON) splitProd
       case maybeRet of
         Nothing -> return ()
         Just (ret) -> do
           let maybeWrappedRet :: Maybe (Either PAe.DecodingError WireRequest)
               maybeWrappedRet = case ret of
                                             Left parseErr -> pure $ Left $ PAe.AttoparsecError parseErr
                                             Right (Just a) -> case A.fromJSON a of
                                                                 A.Error err -> pure $ Left $ PAe.FromJSONError err
                                                                 A.Success wireReq -> pure $ Right wireReq
                                             Right Nothing -> Nothing
           case maybeWrappedRet of
             Just wrappedRet -> P.yield wrappedRet
             Nothing -> return ()
           -- leftoverProd is guaranteed to be empty by the use of A8.endOfInput in ap1
           newProd <- lift $ P.runEffect (leftoverProd P.>-> P.drain)
           -- recur into parseFrames to parse the next line, drop the leading '\n'
           parseFrames (PB.drop (1::Int) newProd)

-- to help with type inference
printTest :: (MonadIO m) => P.Consumer' [Int] m r
printTest = P.print

-- ---------------------------------------------------------------------

wireToChannel :: Chan ChannelResponse -> RequestId -> WireRequest -> ChannelRequest
wireToChannel cout ri wr =
  CReq
    { cinPlugin = plugin
    , cinReqId = ri
    , cinReq = IdeRequest
                 { ideCommand = T.tail command
                 , ideParams  = params wr
                 }
    , cinReplyChan = cout
    }
    where
      (plugin,command) = T.break (==':') (cmd wr)

-- ---------------------------------------------------------------------

channelToWire :: ChannelResponse -> WireResponse
channelToWire cr =
  case coutResp cr of
    IdeResponseOk v -> Ok $ A.toJSON v
    IdeResponseFail v -> Fail $ A.toJSON v
    IdeResponseError v -> HieError $ A.toJSON v

-- ---------------------------------------------------------------------

data WireRequest = WireReq
  { cmd     :: T.Text -- ^combination of PluginId ":" CommandName
  , params  :: ParamMap
  } deriving (Show,Eq)

instance A.ToJSON WireRequest where
    toJSON wr = A.object
                [ "cmd" A..= cmd wr
                , "params" A..= params wr
                ]


instance A.FromJSON WireRequest where
    parseJSON (A.Object v) = WireReq <$>
                           v A..: "cmd" <*>
                           v A..:? "params" A..!= Map.empty
    -- A non-Object value is of the wrong type, so fail.
    parseJSON _          = mzero

-- ---------------------------------------------------------------------

data WireResponse = Ok A.Value | Fail A.Value | HieError A.Value
                  deriving (Show,Eq)

instance A.ToJSON WireResponse where
    toJSON (Ok val) = A.object
                      [ "tag" A..= ("Ok" :: T.Text)
                      , "contents" A..= val
                      ]
    toJSON (Fail val) = A.object
                      [ "tag" A..= ("Fail" :: T.Text)
                      , "contents" A..= val
                      ]
    toJSON (HieError val) = A.object
                      [ "tag" A..= ("HieError" :: T.Text)
                      , "contents" A..= val
                      ]


instance A.FromJSON WireResponse where
    parseJSON (A.Object v) = ((v A..: "tag") >>= decode) <*>
                             v A..: "contents"
      where
        decode "Ok" = pure Ok
        decode "Fail" = pure Fail
        decode "HieError" = pure HieError
        decode tag = fail ("Unrecognized tag '" ++ tag ++ "'")
    -- A non-Object value is of the wrong type, so fail.
    parseJSON _          = mzero
