module Authentication exposing (EnclosedUserData, HypaethralUserData, Method(..), decodeEnclosed, decodeHypaethral, decodeMethod, emptyHypaethralUserData, enclosedDecoder, encodeEnclosed, encodeHypaethral, encodeMethod, hypaethralDecoder, methodFromString, methodToString)

import Json.Decode as Json
import Json.Decode.Ext as Json
import Json.Decode.Pipeline exposing (optional, required)
import Json.Encode
import Maybe.Extra as Maybe
import Sources
import Sources.Encoding as Sources
import Tracks
import Tracks.Encoding as Tracks



-- 🌳


type Method
    = Ipfs
    | Local


type alias EnclosedUserData =
    { backgroundImage : Maybe String
    , repeat : Bool
    , shuffle : Bool
    }


type alias HypaethralUserData =
    { favourites : List Tracks.Favourite
    , sources : List Sources.Source
    , tracks : List Tracks.Track
    }



-- 🔱


emptyHypaethralUserData : HypaethralUserData
emptyHypaethralUserData =
    { favourites = []
    , sources = []
    , tracks = []
    }


methodToString : Method -> String
methodToString method =
    case method of
        Ipfs ->
            "IPFS"

        Local ->
            "LOCAL"


methodFromString : String -> Maybe Method
methodFromString string =
    case string of
        "IPFS" ->
            Just Ipfs

        "LOCAL" ->
            Just Local

        _ ->
            Nothing



-- 🔱  ░░  DECODING & ENCODING


decodeEnclosed : Json.Value -> Result Json.Error EnclosedUserData
decodeEnclosed =
    Json.decodeValue enclosedDecoder


decodeHypaethral : Json.Value -> Result Json.Error HypaethralUserData
decodeHypaethral =
    Json.decodeValue hypaethralDecoder


decodeMethod : Json.Value -> Maybe Method
decodeMethod =
    Json.decodeValue (Json.map methodFromString Json.string) >> Result.toMaybe >> Maybe.join


enclosedDecoder : Json.Decoder EnclosedUserData
enclosedDecoder =
    Json.succeed EnclosedUserData
        |> required "backgroundImage" (Json.maybe Json.string)
        |> optional "repeat" Json.bool False
        |> optional "shuffle" Json.bool False


encodeEnclosed : EnclosedUserData -> Json.Value
encodeEnclosed { backgroundImage, repeat, shuffle } =
    Json.Encode.object
        [ ( "backgroundImage", Json.Encode.string (Maybe.withDefault "" backgroundImage) )
        , ( "repeat", Json.Encode.bool repeat )
        , ( "shuffle", Json.Encode.bool shuffle )
        ]


encodeHypaethral : HypaethralUserData -> Json.Value
encodeHypaethral { favourites, sources, tracks } =
    Json.Encode.object
        [ ( "favourites", Json.Encode.list Tracks.encodeFavourite favourites )
        , ( "sources", Json.Encode.list Sources.encode sources )
        , ( "tracks", Json.Encode.list Tracks.encodeTrack tracks )
        ]


encodeMethod : Method -> Json.Value
encodeMethod =
    methodToString >> Json.Encode.string


hypaethralDecoder : Json.Decoder HypaethralUserData
hypaethralDecoder =
    Json.succeed HypaethralUserData
        |> optional "favourites" (Json.listIgnore Tracks.favouriteDecoder) []
        |> optional "sources" (Json.listIgnore Sources.decoder) []
        |> optional "tracks" (Json.listIgnore Tracks.trackDecoder) []
