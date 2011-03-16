{-# LANGUAGE OverloadedStrings #-}

module Aws.S3.Query
where

import           Aws.Credentials
import           Aws.Http
import           Aws.Query
import           Aws.S3.Info
import           Aws.Signature
import           Aws.Util
import           Data.Maybe
import           Data.Time
import qualified Data.Ascii           as A
import qualified Data.ByteString      as B
import qualified Data.ByteString.Lazy as L
import qualified Network.HTTP.Types   as HTTP

s3SignQuery :: () -> S3Info -> SignatureData -> SignedQuery
s3SignQuery x si sd 
    = SignedQuery {
        sqMethod = Get
      , sqProtocol = s3Protocol si
      , sqHost = endpointHost endpoint
      , sqPort = s3Port si
      , sqPath = path
      , sqQuery = query
      , sqDate = Just $ signatureTime sd
      , sqAuthorization = authorization
      , sqContentType = Nothing
      , sqContentMd5 = Nothing
      , sqBody = L.empty
      , sqStringToSign = stringToSign
      }
    where
      endpoint = s3Endpoint si
      method = Get
      contentMd5 = Nothing
      contentType = Nothing
      path = "/"
      canonicalizedResource = "/"
      ti = case (s3UseUri si, signatureTimeInfo sd) of
             (False, ti') -> ti'
             (True, AbsoluteTimestamp time) -> AbsoluteExpires $ s3DefaultExpiry si `addUTCTime` time
             (True, AbsoluteExpires time) -> AbsoluteExpires time
      cr = signatureCredentials sd
      sig = signature cr HmacSHA1 stringToSign
      stringToSign = B.intercalate "\n" $ concat [[A.toByteString $ httpMethod method]
                                                 , [fromMaybe "" contentMd5]
                                                 , [fromMaybe "" contentType]
                                                 , [A.toByteString $ case ti of
                                                                       AbsoluteTimestamp time -> fmtRfc822Time time
                                                                       AbsoluteExpires time -> fmtTimeEpochSeconds time]
                                                 , [] -- canonicalized AMZ headers
                                                 , [canonicalizedResource]]
      (authorization, query) = case ti of
                                 AbsoluteTimestamp _ -> (Just $ A.unsafeFromByteString $ B.concat ["AWS ", accessKeyID cr, ":", sig], [])
                                 AbsoluteExpires time -> (Nothing, HTTP.simpleQueryToQuery $ authQuery time)
      authQuery time
          = [("Expires", A.toByteString $ fmtTimeEpochSeconds time)
            , ("AWSAccessKeyId", accessKeyID cr)
            , ("SignatureMethod", "HmacSHA256")
            , ("Signature", sig)]