module UI.Queue exposing (initialModel, update, view)

import Chunky exposing (..)
import Conditional exposing (..)
import Html.Styled as Html exposing (Html, fromUnstyled, text)
import List.Extra as List
import Material.Icons exposing (Coloring(..))
import Material.Icons.Action as Icons
import Material.Icons.Image as Icons
import Material.Icons.Navigation as Icons
import Queue exposing (..)
import Return3 as Return exposing (..)
import Tachyons.Classes as T
import Time
import Tracks exposing (IdentifiedTrack)
import UI.Kit
import UI.List
import UI.Navigation exposing (..)
import UI.Page as Page
import UI.Ports as Ports
import UI.Queue.Common exposing (makeItem)
import UI.Queue.Core exposing (..)
import UI.Queue.Fill as Fill
import UI.Queue.Page as Queue exposing (Page(..))
import UI.Reply exposing (Reply(..))



-- 🌳


initialModel : Model
initialModel =
    { activeItem = Nothing
    , future = []
    , ignored = []
    , past = []

    --
    , repeat = False
    , shuffle = False
    }



-- 📣


update : Msg -> Model -> Return Model Msg Reply
update msg model =
    case msg of
        ShowFutureItemMenu item mouseEvent ->
            let
                coordinates =
                    ( mouseEvent.clientPos
                    , mouseEvent.offsetPos
                    )
                        |> (\( ( a, b ), ( c, d ) ) ->
                                { x = a - c + 8
                                , y = b - d + 8
                                }
                           )
            in
            item
                |> ShowFutureQueueItemMenu coordinates
                |> returnReplyWithModel model

        ------------------------------------
        -- Combos
        ------------------------------------
        InjectFirstAndPlay identifiedTrack ->
            [ identifiedTrack ]
                |> InjectFirst { showNotification = False }
                |> updateWithModel model
                |> andThen (update Shift)

        ------------------------------------
        -- Future
        ------------------------------------
        -- # InjectFirst
        -- > Add an item in front of the queue.
        --
        InjectFirst { showNotification } identifiedTracks ->
            let
                ( items, tracks ) =
                    ( List.map (makeItem True) identifiedTracks
                    , List.map Tuple.second identifiedTracks
                    )

                cleanedFuture =
                    List.foldl
                        (\track future ->
                            Fill.cleanAutoGenerated model.shuffle track.id future
                        )
                        model.future
                        tracks
            in
            [ case tracks of
                [ t ] ->
                    ("__" ++ t.tags.title ++ "__ will be played next")
                        |> ShowSuccessNotification

                list ->
                    list
                        |> List.length
                        |> String.fromInt
                        |> (\s -> "__" ++ s ++ " tracks__ will be played next")
                        |> ShowSuccessNotification
            ]
                |> (\list -> ifThenElse showNotification list [])
                |> returnRepliesWithModel { model | future = items ++ cleanedFuture }
                |> addReply FillQueue

        -- # InjectLast
        -- > Add an item after the last manual entry
        --   (ie. after the last injected item).
        --
        InjectLast { showNotification } identifiedTracks ->
            let
                ( items, tracks ) =
                    ( List.map (makeItem True) identifiedTracks
                    , List.map Tuple.second identifiedTracks
                    )

                cleanedFuture =
                    List.foldl
                        (\track future ->
                            Fill.cleanAutoGenerated model.shuffle track.id future
                        )
                        model.future
                        tracks

                manualItems =
                    cleanedFuture
                        |> List.filter (.manualEntry >> (==) True)
                        |> List.length

                newFuture =
                    []
                        ++ List.take manualItems cleanedFuture
                        ++ items
                        ++ List.drop manualItems cleanedFuture
            in
            [ case tracks of
                [ t ] ->
                    ("__" ++ t.tags.title ++ "__ was added to the queue")
                        |> ShowSuccessNotification

                list ->
                    list
                        |> List.length
                        |> String.fromInt
                        |> (\s -> "__" ++ s ++ " tracks__ were added to the queue")
                        |> ShowSuccessNotification
            ]
                |> (\list -> ifThenElse showNotification list [])
                |> returnRepliesWithModel { model | future = newFuture }
                |> addReply FillQueue

        -----------------------------------------
        -- Position
        -----------------------------------------
        -- # Rewind
        -- > Put the next item in the queue as the current one.
        --
        Rewind ->
            changeActiveItem
                (List.last model.past)
                { model
                    | future =
                        model.activeItem
                            |> Maybe.map (\item -> item :: model.future)
                            |> Maybe.withDefault model.future
                    , past =
                        model.past
                            |> List.init
                            |> Maybe.withDefault []
                }

        -- # Shift
        -- > Put the next item in the queue as the current one.
        --
        Shift ->
            changeActiveItem
                (List.head model.future)
                { model
                    | future =
                        model.future
                            |> List.drop 1
                    , past =
                        model.activeItem
                            |> Maybe.map List.singleton
                            |> Maybe.map (List.append model.past)
                            |> Maybe.withDefault model.past
                }

        ------------------------------------
        -- Contents
        ------------------------------------
        -- # Clear
        --
        Clear ->
            returnRepliesWithModel
                { model | future = [], ignored = [] }
                [ FillQueue ]

        -- # Fill
        -- > Fill the queue with items.
        --
        Fill timestamp tracks ->
            return (fillQueue timestamp tracks model)

        -- # Reset
        -- > Renew the queue, meaning that the auto-generated items in the queue
        --   are removed and new items are added.
        --
        Reset ->
            let
                newFuture =
                    List.filter (.manualEntry >> (==) True) model.future
            in
            returnRepliesWithModel
                { model | future = newFuture, ignored = [] }
                [ FillQueue ]

        ------------------------------------
        -- Settings
        ------------------------------------
        ToggleRepeat ->
            ( { model | repeat = not model.repeat }
            , Ports.setRepeat (not model.repeat)
            , [ SaveEnclosedUserData ]
            )

        ToggleShuffle ->
            { model | shuffle = not model.shuffle }
                |> update Reset
                |> addReply SaveEnclosedUserData


updateWithModel : Model -> Msg -> Return Model Msg Reply
updateWithModel model msg =
    update msg model



-- 📣  ░░  COMMON


changeActiveItem : Maybe Item -> Model -> Return Model Msg Reply
changeActiveItem maybeItem model =
    returnRepliesWithModel
        { model | activeItem = maybeItem }
        [ ActiveQueueItemChanged maybeItem
        , FillQueue
        ]


fillQueue : Time.Posix -> List IdentifiedTrack -> Model -> Model
fillQueue timestamp availableTracks model =
    let
        nonMissingTracks =
            List.filter
                (Tuple.second >> .id >> (/=) Tracks.missingId)
                availableTracks
    in
    model
        |> (\m ->
                -- Empty the ignored list when we are ignoring all the tracks
                if List.length model.ignored == List.length nonMissingTracks then
                    { m | ignored = [] }

                else
                    m
           )
        |> (\m ->
                -- Fill using the appropiate method
                case m.shuffle of
                    False ->
                        { m | future = Fill.ordered timestamp nonMissingTracks m }

                    True ->
                        { m | future = Fill.shuffled timestamp nonMissingTracks m }
           )



-- 🗺


view : Queue.Page -> Model -> Html Msg
view page model =
    UI.Kit.receptacle
        (case page of
            History ->
                historyView model

            Index ->
                futureView model
        )



-- 🗺  ░░  FUTURE


futureView : Model -> List (Html Msg)
futureView model =
    [ -----------------------------------------
      -- Navigation
      -----------------------------------------
      UI.Navigation.local
        [ ( Icon Icons.arrow_back
          , Label "Back to list" Hidden
          , NavigateToPage Page.Index
          )
        , ( Icon Icons.event_seat
          , Label "History" Shown
          , NavigateToPage (Page.Queue History)
          )
        , ( Icon Icons.cancel
          , Label "Clear all" Shown
          , PerformMsg Clear
          )
        , ( Icon Icons.restore
          , Label "Clear ignored" Shown
          , PerformMsg Reset
          )
        ]

    -----------------------------------------
    -- Content
    -----------------------------------------
    , UI.Kit.canister
        [ UI.Kit.h1 "Up next"
        , model.future
            |> List.indexedMap futureItem
            |> UI.List.view
            |> chunky [ T.mt3 ]
        ]
    ]


futureItem : Int -> Queue.Item -> UI.List.Item Msg
futureItem idx item =
    let
        ( _, track ) =
            item.identifiedTrack
    in
    { label =
        inline
            [ ifThenElse item.manualEntry T.o_100 T.o_50 ]
            [ inline
                [ T.dib, T.f7, T.mr2 ]
                [ text (String.fromInt <| idx + 1), text "." ]
            , text (track.tags.artist ++ " - " ++ track.tags.title)
            ]
    , actions =
        []
    }



-- 🗺  ░░  HISTORY


historyView : Model -> List (Html Msg)
historyView model =
    [ -----------------------------------------
      -- Navigation
      -----------------------------------------
      UI.Navigation.local
        [ ( Icon Icons.arrow_back
          , Label "Back to list" Hidden
          , NavigateToPage Page.Index
          )
        , ( Icon Icons.event_seat
          , Label "Up next" Shown
          , NavigateToPage (Page.Queue Index)
          )
        ]

    -----------------------------------------
    -- Content
    -----------------------------------------
    , if List.isEmpty model.past then
        chunk
            [ T.relative ]
            [ chunk
                [ T.absolute, T.left_0, T.top_0 ]
                [ UI.Kit.canister [ UI.Kit.h1 "History" ] ]
            ]

      else
        UI.Kit.canister
            [ UI.Kit.h1 "History"
            , model.past
                |> List.reverse
                |> List.indexedMap historyItem
                |> UI.List.view
                |> chunky [ T.mt3 ]
            ]

    --
    , if List.isEmpty model.past then
        UI.Kit.centeredContent
            [ chunk
                [ T.o_30 ]
                [ fromUnstyled (Icons.music_note 64 Inherit) ]
            , chunk
                [ T.lh_copy, T.mt2, T.o_40, T.tc ]
                [ text "Nothing here yet,"
                , lineBreak
                , text "play some music first."
                ]
            ]

      else
        nothing
    ]


historyItem : Int -> Queue.Item -> UI.List.Item Msg
historyItem idx { identifiedTrack, manualEntry } =
    let
        ( _, track ) =
            identifiedTrack
    in
    { label =
        inline
            [ ifThenElse manualEntry T.o_100 T.o_50 ]
            [ inline
                [ T.dib, T.f7, T.mr2 ]
                [ text (String.fromInt <| idx + 1), text "." ]
            , text (track.tags.artist ++ " - " ++ track.tags.title)
            ]
    , actions = []
    }
