{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}

module Network.Wai.Middleware.StripHeadersSpec (
    main,
    spec,
) where

import Control.Arrow (first)
import Data.ByteString (ByteString)
import qualified Data.CaseInsensitive as CI
#if __GLASGOW_HASKELL__ < 804
import Data.Monoid ((<>))
#endif
import Network.HTTP.Types (status200)
import Network.Wai
import Network.Wai.Test (SResponse (simpleHeaders), request, runSession)
import Test.Hspec

import Network.Wai.Middleware.AddHeaders (addHeaders)
import Network.Wai.Middleware.StripHeaders (stripHeaderIf, stripHeadersIf)

main :: IO ()
main = hspec spec

spec :: Spec
spec = describe "stripHeader" $ do
    let host = "example.com"
    let ciTestHeaders = map (first CI.mk) testHeaders

    it "strips a specific header" $ do
        resp1 <- runApp host (addHeaders testHeaders) defaultRequest
        resp2 <-
            runApp
                host
                (stripHeaderIf "Foo" (const False) . addHeaders testHeaders)
                defaultRequest
        resp3 <-
            runApp
                host
                (stripHeaderIf "Foo" (const True) . addHeaders testHeaders)
                defaultRequest

        simpleHeaders resp1 `shouldBe` ciTestHeaders
        simpleHeaders resp2 `shouldBe` ciTestHeaders
        simpleHeaders resp3 `shouldBe` drop 1 ciTestHeaders

    it "strips specific set of headers" $ do
        resp1 <- runApp host (addHeaders testHeaders) defaultRequest
        resp2 <-
            runApp
                host
                (stripHeadersIf ["Bar", "Foo"] (const False) . addHeaders testHeaders)
                defaultRequest
        resp3 <-
            runApp
                host
                (stripHeadersIf ["Bar", "Foo"] (const True) . addHeaders testHeaders)
                defaultRequest

        simpleHeaders resp1 `shouldBe` ciTestHeaders
        simpleHeaders resp2 `shouldBe` ciTestHeaders
        simpleHeaders resp3 `shouldBe` [last ciTestHeaders]

testHeaders :: [(ByteString, ByteString)]
testHeaders = [("Foo", "fooey"), ("Bar", "barbican"), ("Baz", "bazooka")]

runApp :: ByteString -> Middleware -> Request -> IO SResponse
runApp host mw req =
    runSession
        (request req{requestHeaderHost = Just $ host <> ":80"})
        $ mw app
  where
    app _ respond = respond $ responseLBS status200 [] ""
