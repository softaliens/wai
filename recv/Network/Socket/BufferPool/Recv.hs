{-# LANGUAGE OverloadedStrings #-}

module Network.Socket.BufferPool.Recv (
    receive,
    makeRecvN,
) where

import qualified Data.ByteString as BS
import Data.ByteString.Internal (ByteString (..), unsafeCreate)
import Data.IORef
import Network.Socket (Socket, recvBuf)

import Network.Socket.BufferPool.Buffer
import Network.Socket.BufferPool.Types

----------------------------------------------------------------

-- | The receiving function with a buffer pool.
--   The buffer pool is automatically managed.
receive :: Socket -> BufferPool -> Recv
receive sock pool = withBufferPool pool $ \ptr size -> recvBuf sock ptr size

----------------------------------------------------------------

-- | This function returns a receiving function
--   based on two receiving functions.
--   The returned function receives exactly N bytes.
--   The first argument is an initial received data.
--   After consuming the initial data, the two functions is used.
--   When N is less than equal to 4096, the buffer pool is used.
--   Otherwise, a new buffer is allocated.
--   In this case, the global lock is taken.
makeRecvN :: ByteString -> Recv -> IO RecvN
makeRecvN bs0 recv = do
    ref <- newIORef bs0
    return $ recvN ref recv

-- | The receiving function which receives exactly N bytes
--   (the fourth argument).
recvN :: IORef ByteString -> Recv -> RecvN
recvN ref recv size = do
    cached <- readIORef ref
    (bs, leftover) <- tryRecvN cached size recv
    writeIORef ref leftover
    return bs

----------------------------------------------------------------

tryRecvN :: ByteString -> Int -> IO ByteString -> IO (ByteString, ByteString)
tryRecvN init0 siz0 recv
    | siz0 <= len0 = return $ BS.splitAt siz0 init0
    | otherwise = go (init0 :) (siz0 - len0)
  where
    len0 = BS.length init0
    go build left = do
        bs <- recv
        let len = BS.length bs
        if len == 0
            then return ("", "")
            else
                if len >= left
                    then do
                        let (consume, leftover) = BS.splitAt left bs
                            ret = concatN siz0 $ build [consume]
                        return (ret, leftover)
                    else do
                        let build' = build . (bs :)
                            left' = left - len
                        go build' left'

concatN :: Int -> [ByteString] -> ByteString
concatN total bss0 = unsafeCreate total $ \ptr -> goCopy bss0 ptr
  where
    goCopy [] _ = return ()
    goCopy (bs : bss) ptr = do
        ptr' <- copy ptr bs
        goCopy bss ptr'
