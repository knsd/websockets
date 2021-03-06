-- | Demultiplexing of frames into messages
module Network.WebSockets.Protocol.Hybi10.Demultiplex
    ( FrameType (..)
    , Frame (..)
    , DemultiplexState
    , emptyDemultiplexState
    , demultiplex
    ) where

import Blaze.ByteString.Builder (Builder)
import Data.Monoid (mappend)
import qualified Blaze.ByteString.Builder as B
import qualified Data.ByteString.Lazy as BL

import Network.WebSockets.Types

-- | A low-level representation of a WebSocket packet
data Frame = Frame
    { frameFin     :: !Bool
    , frameType    :: !FrameType
    , framePayload :: !BL.ByteString
    } deriving (Eq, Show)

-- | The type of a frame. Not all types are allowed for all protocols.
data FrameType
    = ContinuationFrame
    | TextFrame
    | BinaryFrame
    | CloseFrame
    | PingFrame
    | PongFrame
    deriving (Eq, Show)

-- | Internal state used by the demultiplexer
newtype DemultiplexState = DemultiplexState
    { unDemultiplexState :: Maybe (FrameType, Builder)
    }

emptyDemultiplexState :: DemultiplexState
emptyDemultiplexState = DemultiplexState Nothing

demultiplex :: DemultiplexState
            -> Frame
            -> (Maybe (Message p), DemultiplexState)
demultiplex state (Frame fin tp pl) = case tp of
    -- Return control messages immediately, they have no influence on the state
    CloseFrame  -> (Just (ControlMessage (Close pl)), state)
    PingFrame   -> (Just (ControlMessage (Ping pl)), state)
    PongFrame   -> (Just (ControlMessage (Pong pl)), state)
    -- If we're dealing with a continuation...
    ContinuationFrame -> case unDemultiplexState state of
        -- We received a continuation but we don't have any state. Let's ignore
        -- this fragment...
        Nothing -> (Nothing, DemultiplexState Nothing)
        -- Append the payload to the state
        -- TODO: protect against overflows
        Just (amt, b)
            | not fin   -> (Nothing, DemultiplexState (Just (amt, b')))
            | otherwise -> case amt of
                TextFrame   -> (Just (DataMessage (Text m)), e)
                BinaryFrame -> (Just (DataMessage (Binary m)), e)
                _           -> error "Demultiplex.demultiplex: Internal error"
          where
            b' = b `mappend` plb
            m = B.toLazyByteString b'
    TextFrame
        | fin       -> (Just (DataMessage (Text pl)), e)
        | otherwise -> (Nothing, DemultiplexState (Just (TextFrame, plb)))
    BinaryFrame
        | fin       -> (Just (DataMessage (Binary pl)), e)
        | otherwise -> (Nothing, DemultiplexState (Just (BinaryFrame, plb)))
  where
    e = emptyDemultiplexState
    plb = B.fromLazyByteString pl
