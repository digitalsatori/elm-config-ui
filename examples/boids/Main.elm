port module Main exposing (main)

import Array exposing (Array)
import Array.Extra
import Browser
import Browser.Events
import Color exposing (Color)
import Config exposing (Config)
import ConfigForm as ConfigForm exposing (ConfigForm)
import Dict exposing (Dict)
import Direction2d exposing (Direction2d)
import Html exposing (Html)
import Html.Attributes exposing (style)
import Html.Events
import Html.Events.Extra.Pointer as Pointer
import Json.Decode as JD
import Json.Decode.Pipeline as JDP
import Json.Encode as JE
import List.Extra
import Point2d exposing (Point2d)
import Random
import Random.Array
import Round
import Svg exposing (Svg)
import Svg.Attributes
import Vector2d exposing (Vector2d)


log : String -> a -> a
log msg val =
    let
        {--
        _ =
            Debug.log msg val

        --}
        _ =
            0
    in
    val


port sendToPort : JD.Value -> Cmd msg


port receiveFromPort : (JD.Value -> msg) -> Sub msg


main =
    Browser.element
        { init = init
        , view = view
        , update = updateResult
        , subscriptions = subscriptions
        }


type alias ModelResult =
    Result String Model


type alias Model =
    { config : Config
    , configForm : ConfigForm Config
    , isConfigOpen : Bool
    , boids : Array Boid
    , seed : Random.Seed
    , mousePos : Maybe Point2d
    , selectedBoidIndex : Maybe Int
    }


type alias Boid =
    { pos : Point2d
    , vel : Vector2d
    , velForCohesion : Vector2d
    , velForAlignment : Vector2d
    , velForSeparation : Vector2d
    , velForMouse : Vector2d
    , velForMomentum : Vector2d
    , color : Color
    }


type Msg
    = ConfigFormMsg (ConfigForm.Msg Config)
    | ReceivedFromPort JE.Value
    | ClickedOpenConfig
    | ClickedCloseConfig
    | Tick Float
    | MouseMoved Point2d
    | MouseClicked Point2d
    | MouseLeft



-- FLAGS


type alias Flags =
    { localStorage : LocalStorage
    , configFile : JE.Value
    , timestamp : Int
    }


type alias LocalStorage =
    { configForm : JE.Value

    -- other things you may not necessarily want in your config form
    , isConfigOpen : Bool
    }


decodeFlags : JD.Decoder Flags
decodeFlags =
    JD.succeed Flags
        |> JDP.required "localStorage" decodeLocalStorage
        |> JDP.required "configFile" JD.value
        |> JDP.required "timestamp" JD.int


decodeLocalStorage : JD.Decoder LocalStorage
decodeLocalStorage =
    JD.succeed LocalStorage
        |> JDP.optional "configForm" JD.value (JE.object [])
        |> JDP.optional "isConfigOpen" JD.bool False



-- INIT


init : JE.Value -> ( ModelResult, Cmd Msg )
init jsonFlags =
    case JD.decodeValue decodeFlags jsonFlags of
        Ok flags ->
            let
                ( config, configForm ) =
                    ConfigForm.init
                        { configJson = flags.configFile
                        , configFormJson = flags.localStorage.configForm
                        , logics = Config.logics
                        , emptyConfig =
                            Config.empty
                                { int = 1
                                , float = 1
                                , string = "SORRY IM NEW HERE"
                                , bool = True
                                , color = Color.rgba 1 0 1 1 -- hot pink!
                                }
                        }

                ( boids, seed ) =
                    Random.step
                        (Random.Array.array config.numBoids (boidGenerator config))
                        (Random.initialSeed flags.timestamp)
            in
            ( Ok
                { config = config
                , configForm = configForm
                , isConfigOpen = flags.localStorage.isConfigOpen
                , boids = boids
                , seed = seed
                , mousePos = Nothing
                , selectedBoidIndex = Just 0
                }
            , Cmd.none
            )

        Err err ->
            ( Err (JD.errorToString err)
            , Cmd.none
            )


boidGenerator : Config -> Random.Generator Boid
boidGenerator config =
    Random.map4
        (\x y angle color ->
            { pos = Point2d.fromCoordinates ( x, y )
            , vel =
                ( config.maxSpeed, angle )
                    |> fromPolar
                    |> Vector2d.fromComponents
            , velForCohesion = Vector2d.zero
            , velForAlignment = Vector2d.zero
            , velForSeparation = Vector2d.zero
            , velForMouse = Vector2d.zero
            , velForMomentum = Vector2d.zero
            , color = color
            }
        )
        (Random.float 0 config.viewportWidth)
        (Random.float 0 config.viewportHeight)
        (Random.float 0 (2 * pi))
        colorGenerator


updateResult : Msg -> ModelResult -> ( ModelResult, Cmd Msg )
updateResult msg modelResult =
    case modelResult of
        Ok model ->
            update msg model
                |> Tuple.mapFirst Ok

        Err _ ->
            ( modelResult, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ConfigFormMsg configFormMsg ->
            let
                ( newConfig, newConfigForm, maybeJsonCmd ) =
                    ConfigForm.update
                        Config.logics
                        model.config
                        model.configForm
                        configFormMsg

                newModel =
                    { model
                        | config = newConfig
                        , configForm = newConfigForm
                    }
            in
            ( newModel
                |> updateBoidCount
            , Cmd.batch
                [ saveToLocalStorageCmd newModel
                , case maybeJsonCmd of
                    Just jsonCmd ->
                        sendToPort
                            (JE.object
                                [ ( "id", JE.string "CONFIG" )
                                , ( "val", jsonCmd )
                                ]
                            )

                    Nothing ->
                        Cmd.none
                ]
            )

        ReceivedFromPort portJson ->
            case JD.decodeValue fromPortDecoder portJson of
                Ok receiveMsg ->
                    case receiveMsg of
                        ConfigFormPortMsg json ->
                            let
                                ( newConfig, newConfigForm, maybeJsonCmd ) =
                                    ConfigForm.updateFromJson
                                        Config.logics
                                        model.config
                                        model.configForm
                                        json

                                newModel =
                                    { model
                                        | config = newConfig
                                        , configForm = newConfigForm
                                    }
                            in
                            ( newModel
                                |> updateBoidCount
                            , Cmd.batch
                                [ saveToLocalStorageCmd newModel
                                , case maybeJsonCmd of
                                    Just jsonCmd ->
                                        sendToPort
                                            (JE.object
                                                [ ( "id", JE.string "CONFIG" )
                                                , ( "val", jsonCmd )
                                                ]
                                            )

                                    Nothing ->
                                        Cmd.none
                                ]
                            )

                Err err ->
                    let
                        _ =
                            log "Could not decode incoming port msg: " (JD.errorToString err)
                    in
                    ( model, Cmd.none )

        ClickedOpenConfig ->
            let
                newModel =
                    { model | isConfigOpen = True }
            in
            ( newModel
            , saveToLocalStorageCmd newModel
            )

        ClickedCloseConfig ->
            let
                newModel =
                    { model | isConfigOpen = False }
            in
            ( newModel
            , saveToLocalStorageCmd newModel
            )

        Tick delta ->
            let
                scaledDelta =
                    model.config.timeScale * delta
            in
            ( { model
                | boids = moveBoids model scaledDelta
              }
            , Cmd.none
            )

        MouseMoved pos ->
            ( { model | mousePos = Just pos }
            , Cmd.none
            )

        MouseClicked pos ->
            ( { model
                | selectedBoidIndex =
                    getBoidAt pos model
              }
            , Cmd.none
            )

        MouseLeft ->
            ( { model | mousePos = Nothing }
            , Cmd.none
            )


updateBoidCount : Model -> Model
updateBoidCount model =
    let
        boidDiff =
            model.config.numBoids - Array.length model.boids
    in
    if boidDiff > 0 then
        -- add more
        let
            ( newBoids, seed ) =
                Random.step
                    (Random.Array.array boidDiff (boidGenerator model.config))
                    model.seed
        in
        { model
            | boids = Array.append model.boids newBoids
            , seed = seed
        }

    else if boidDiff < 0 then
        let
            ( decreasedBoids, newSelectedIndex ) =
                case model.selectedBoidIndex of
                    Just index ->
                        if index <= model.config.numBoids then
                            case Array.get index model.boids of
                                Just selectedBoid ->
                                    ( model.boids
                                        |> Array.slice 0 (model.config.numBoids - 1)
                                        |> Array.append (Array.fromList [ selectedBoid ])
                                    , Just 0
                                    )

                                Nothing ->
                                    ( model.boids
                                        |> Array.slice 0 model.config.numBoids
                                      -- should never happen, so reset selectedIndex
                                    , Nothing
                                    )

                        else
                            ( model.boids
                                |> Array.slice 0 model.config.numBoids
                            , Just index
                            )

                    Nothing ->
                        ( model.boids
                            |> Array.slice 0 model.config.numBoids
                        , Nothing
                        )
        in
        { model
            | boids = decreasedBoids
            , selectedBoidIndex = newSelectedIndex
        }

    else
        model


getBoidAt : Point2d -> Model -> Maybe Int
getBoidAt pos model =
    -- TODO torus
    model.boids
        |> Array.toIndexedList
        |> List.Extra.find
            (\( i, boid ) ->
                (boid.pos
                    |> Point2d.squaredDistanceFrom pos
                )
                    <= (model.config.boidRad ^ 2)
            )
        |> Maybe.map Tuple.first


getHoveredBoidIndex : Model -> Maybe Int
getHoveredBoidIndex model =
    -- TODO torus
    case model.mousePos of
        Just mousePos ->
            model.boids
                |> Array.toIndexedList
                |> List.Extra.find
                    (\( i, boid ) ->
                        (boid.pos
                            |> Point2d.squaredDistanceFrom mousePos
                        )
                            <= (model.config.boidRad ^ 2)
                    )
                |> Maybe.map Tuple.first

        Nothing ->
            Nothing


moveBoids : Model -> Float -> Array Boid
moveBoids model delta =
    model.boids
        |> mapOthers
            (moveBoid
                model.config
                model.mousePos
                delta
            )


mapOthers : (List a -> a -> b) -> Array a -> Array b
mapOthers func array =
    -- apply a func to an item and all OTHER items in the list
    array
        |> Array.indexedMap
            (\i val ->
                let
                    otherVals =
                        array
                            |> Array.Extra.removeAt i
                            |> Array.toList
                in
                func otherVals val
            )


moveBoid : Config -> Maybe Point2d -> Float -> List Boid -> Boid -> Boid
moveBoid config maybeMousePos delta otherBoids boid =
    let
        velFromRule : Point2d -> Float -> (List Boid -> Vector2d) -> Vector2d
        velFromRule pos range ruleFunc =
            boidsInRange
                ( config.viewportWidth, config.viewportHeight )
                range
                otherBoids
                pos
                |> ruleFunc

        -- cohesion (center of mass)
        velForCohesion =
            velFromRule
                boid.pos
                config.visionRange
                (\nearbyBoids ->
                    let
                        centerOfMass =
                            nearbyBoids
                                |> List.map .pos
                                |> Point2d.centroid
                    in
                    case centerOfMass of
                        Just center ->
                            center
                                |> Vector2d.from boid.pos
                                |> Vector2d.normalize
                                |> Vector2d.scaleBy
                                    (config.cohesionFactor
                                        / toFloat (List.length nearbyBoids)
                                    )

                        Nothing ->
                            Vector2d.zero
                )

        -- alignment
        velForAlignment =
            velFromRule
                boid.pos
                config.visionRange
                (\nearbyBoids ->
                    if List.isEmpty nearbyBoids then
                        Vector2d.zero

                    else
                        nearbyBoids
                            |> List.map .vel
                            |> List.foldl Vector2d.sum Vector2d.zero
                            |> Vector2d.scaleBy
                                (config.alignmentFactor
                                    / toFloat (List.length nearbyBoids)
                                )
                )

        -- separation
        velForSeparation =
            velFromRule
                boid.pos
                (personalSpaceRange config)
                (\nearbyBoids ->
                    -- OLD ALG
                    --let
                    --    centerOfMassOfTooCloseBoids =
                    --        nearbyBoids
                    --            |> List.map .pos
                    --            |> Point2d.centroid
                    --in
                    --case centerOfMassOfTooCloseBoids of
                    --    Just center ->
                    --        center
                    --            |> Vector2d.from boid.pos
                    --            --|> Vector2d.normalize
                    --            |> Vector2d.scaleBy
                    --                (-config.separationFactor
                    --                    / toFloat (List.length nearbyBoids)
                    --                )
                    --    Nothing ->
                    --        Vector2d.zero
                    -- CLASSIC ALG
                    let
                        foo =
                            0
                    in
                    List.foldl
                        (\nearbyBoid tmpVec ->
                            Vector2d.from nearbyBoid.pos boid.pos
                                |> Vector2d.sum tmpVec
                        )
                        Vector2d.zero
                        nearbyBoids
                )

        -- mouse
        velForMouse =
            case ( maybeMousePos, config.mouseFactor > 0 ) of
                ( Just mousePos, True ) ->
                    let
                        distSq =
                            Point2d.squaredDistanceFrom boid.pos mousePos
                    in
                    if distSq <= config.visionRange ^ 2 then
                        boid.pos
                            |> Vector2d.from mousePos
                            |> Vector2d.normalize
                            --|> Vector2d.scaleBy (config.mouseFactor / logBase config.mouseLogBase (sqrt distSq / config.visionRange))
                            |> Vector2d.scaleBy (-1 * config.mouseFactor ^ config.mouseExponent)

                    else
                        Vector2d.zero

                _ ->
                    Vector2d.zero

        -- momentum
        velForMomentum =
            boid.vel
                |> Vector2d.scaleBy config.momentumFactor

        -- wrap it all up
        allVels =
            [ velForCohesion
            , velForSeparation
            , velForAlignment
            , velForMouse
            , velForMomentum
            ]

        newVel =
            allVels
                |> List.foldl Vector2d.sum Vector2d.zero
                --|> Vector2d.scaleBy (1 / toFloat (List.length allVels))
                |> (\v ->
                        if Vector2d.length v > config.maxSpeed then
                            v
                                |> Vector2d.direction
                                |> Maybe.map Direction2d.toVector
                                |> Maybe.withDefault Vector2d.zero
                                |> Vector2d.scaleBy config.maxSpeed

                        else
                            v
                   )

        newPos =
            boid.pos
                |> Point2d.translateBy (Vector2d.scaleBy (delta / 1000) newVel)
                |> Point2d.coordinates
                |> (\( x, y ) ->
                        ( if x < 0 then
                            config.viewportWidth - abs x

                          else if x > config.viewportWidth then
                            x - config.viewportWidth

                          else
                            x
                        , if y < 0 then
                            config.viewportHeight - abs y

                          else if y > config.viewportHeight then
                            y - config.viewportHeight

                          else
                            y
                        )
                   )
                |> Point2d.fromCoordinates
    in
    { boid
        | pos = newPos
        , vel = newVel
        , velForCohesion = velForCohesion
        , velForAlignment = velForAlignment
        , velForSeparation = velForSeparation
        , velForMouse = velForMouse
        , velForMomentum = velForMomentum
    }


wrappedPoses : ( Float, Float ) -> Point2d -> List Point2d
wrappedPoses ( width, height ) pos =
    let
        ( x, y ) =
            pos
                |> Point2d.coordinates

        --wrapped values ought to sometimes be closer than original pos
        wrappedX =
            if x > (width / 2) then
                x - width

            else
                x + width

        wrappedY =
            if y > (height / 2) then
                y - height

            else
                y + height
    in
    [ pos
    , Point2d.fromCoordinates ( x, wrappedY )
    , Point2d.fromCoordinates ( wrappedX, y )
    , Point2d.fromCoordinates ( wrappedX, wrappedY )
    ]


boidsInRange : ( Float, Float ) -> Float -> List Boid -> Point2d -> List Boid
boidsInRange viewport range boids boidPos =
    boids
        |> List.filterMap
            (\otherBoid ->
                let
                    -- TODO perf
                    closestPos =
                        wrappedPoses viewport otherBoid.pos
                            |> List.Extra.minimumBy
                                (Point2d.squaredDistanceFrom boidPos)
                            |> Maybe.withDefault otherBoid.pos
                in
                if Point2d.squaredDistanceFrom boidPos closestPos <= range ^ 2 then
                    Just { otherBoid | pos = closestPos }

                else
                    Nothing
            )


vector2dToStr : Vector2d -> String
vector2dToStr v =
    v
        |> Vector2d.components
        |> (\( x, y ) ->
                [ "("
                , Round.round 2 x
                , " , "
                , Round.round 2 y
                , ")"
                ]
                    |> String.concat
           )


type ReceiveMsg
    = ConfigFormPortMsg JE.Value


fromPortDecoder : JD.Decoder ReceiveMsg
fromPortDecoder =
    JD.field "id" JD.string
        |> JD.andThen
            (\id ->
                case id of
                    "CONFIG" ->
                        JD.field "val" JD.value
                            |> JD.map ConfigFormPortMsg

                    str ->
                        JD.fail ("Bad id to receiveFromPort: " ++ str)
            )


saveToLocalStorageCmd : Model -> Cmd Msg
saveToLocalStorageCmd model =
    sendToPort <|
        JE.object
            [ ( "id", JE.string "SAVE" )
            , ( "val"
              , JE.object
                    [ ( "configForm"
                      , ConfigForm.encodeConfigForm
                            model.configForm
                      )
                    , ( "isConfigOpen"
                      , JE.bool model.isConfigOpen
                      )
                    ]
              )
            ]


view : ModelResult -> Html Msg
view modelResult =
    case modelResult of
        Ok model ->
            Html.div
                [ style "width" "100%"
                , style "height" "100%"
                , style "padding" "20px"
                , style "font-family" "sans-serif"
                , style "box-sizing" "border-box"
                ]
                [ viewBoids model
                , viewConfig model
                , viewInspector model
                ]

        Err err ->
            Html.text err


viewConfig : Model -> Html Msg
viewConfig ({ config } as model) =
    Html.div
        [ style "right" "20px"
        , style "top" "20px"
        , style "position" "absolute"
        , style "height" "100%"
        , style "font-size" "22px"
        ]
        [ Html.div
            [ style "padding" (pxInt config.configTablePadding)
            , style "overflow-y" "auto"
            , style "background" (Color.toCssString config.configTableBgColor)
            , style "border" ("1px solid " ++ Color.toCssString config.configTableBorderColor)
            , style "height" "100%"
            ]
            (if model.isConfigOpen then
                [ Html.button
                    [ style "text-align" "right"
                    , Html.Events.onClick ClickedCloseConfig
                    ]
                    [ Html.text "Close Config"
                    ]
                , ConfigForm.view
                    (ConfigForm.viewOptions
                        |> ConfigForm.withRowSpacing config.configRowSpacing
                        |> ConfigForm.withLabelHighlightBgColor config.configLabelHighlightBgColor
                        |> ConfigForm.withInputWidth config.configInputWidth
                        |> ConfigForm.withInputHeight config.configInputHeight
                        |> ConfigForm.withFontSize config.configFontSize
                    )
                    Config.logics
                    model.configForm
                    |> Html.map ConfigFormMsg
                , Html.textarea
                    [ Html.Attributes.value
                        (ConfigForm.encode
                            Config.logics
                            model.config
                            |> JE.encode 2
                        )
                    ]
                    []
                ]

             else
                [ Html.button
                    [ style "text-align" "right"
                    , Html.Events.onClick ClickedOpenConfig
                    ]
                    [ Html.text "Open Config" ]
                ]
            )
        ]


viewBoids : Model -> Html Msg
viewBoids ({ config } as model) =
    Html.div
        [ style "width" (pxFloat config.viewportWidth)
        , style "height" (pxFloat config.viewportHeight)
        , style "border" "1px solid black"
        ]
        [ Svg.svg
            [ Svg.Attributes.width "100%"
            , Svg.Attributes.height "100%"
            , Pointer.onMove (relativePos >> MouseMoved)
            , Pointer.onDown (relativePos >> MouseClicked)
            , Pointer.onLeave (\_ -> MouseLeft)
            ]
            [ -- sky
              Svg.rect
                [ Svg.Attributes.x "0"
                , Svg.Attributes.y "0"
                , Svg.Attributes.width "100%"
                , Svg.Attributes.height "100%"
                , Svg.Attributes.fill (Color.toCssString config.skyColor)
                , Svg.Attributes.opacity (toOpacityString config.skyColor)
                ]
                []
            , Svg.g []
                (model.boids
                    |> Array.toIndexedList
                    |> List.reverse
                    |> List.map
                        (viewWrappedBoid config
                            [ model.selectedBoidIndex, getHoveredBoidIndex model ]
                        )
                )
            ]
        ]


toOpacity : Color -> Float
toOpacity color =
    color
        |> Color.toRgba
        |> .alpha


toOpacityString : Color -> String
toOpacityString color =
    color
        |> Color.toRgba
        |> .alpha
        |> String.fromFloat


relativePos : Pointer.Event -> Point2d
relativePos event =
    event.pointer.offsetPos
        |> Point2d.fromCoordinates


viewInspector : Model -> Html Msg
viewInspector model =
    case model.selectedBoidIndex of
        Just index ->
            case Array.get index model.boids of
                Just boid ->
                    let
                        rows =
                            [ ( "Cohesion Vel", vector2dToStr boid.velForCohesion )
                            , ( "Alignment Vel", vector2dToStr boid.velForAlignment )
                            , ( "Separation Vel", vector2dToStr boid.velForSeparation )
                            , ( "Vel", vector2dToStr boid.vel )
                            ]
                    in
                    Html.table
                        [ style "background" (Color.toCssString model.config.skyColor)
                        , style "padding" "15px"
                        ]
                        (arrowMapping model.config
                            |> List.map
                                (\( label, color, velFunc ) ->
                                    Html.tr [ style "color" (Color.toCssString color) ]
                                        [ Html.td
                                            [ style "font-weight" "bold" ]
                                            [ Html.text label ]
                                        , Html.td
                                            []
                                            [ Html.text (vector2dToStr <| velFunc boid) ]
                                        ]
                                )
                        )

                Nothing ->
                    Html.text ""

        Nothing ->
            Html.text ""


viewWrappedBoid : Config -> List (Maybe Int) -> ( Int, Boid ) -> Svg Msg
viewWrappedBoid config selectedIndices ( index, boid ) =
    let
        isSelected =
            selectedIndices
                |> List.any (\i -> i == Just index)
    in
    wrappedPoses ( config.viewportWidth, config.viewportHeight ) boid.pos
        |> List.map
            (\pos ->
                viewBoid config isSelected { boid | pos = pos }
            )
        |> Svg.g []


arrowMapping : Config -> List ( String, Color, Boid -> Vector2d )
arrowMapping config =
    [ ( "Momentum", config.momentumColor, .velForMomentum )
    , ( "Cohesion", config.cohesionColor, .velForCohesion )
    , ( "Alignment", config.alignmentColor, .velForAlignment )
    , ( "Separation", config.separationColor, .velForSeparation )
    , ( "Mouse", config.mouseColor, .velForMouse )
    ]


personalSpaceRange : Config -> Float
personalSpaceRange config =
    config.boidRad * config.separationRangeFactor


viewBoid : Config -> Bool -> Boid -> Svg Msg
viewBoid config isSelected boid =
    wrappedPoses
        ( config.viewportWidth, config.viewportHeight )
        boid.pos
        |> List.map
            (\pos ->
                let
                    ( x, y ) =
                        Point2d.coordinates pos

                    ( beakEndpointX, beakEndpointY ) =
                        pos
                            |> Point2d.translateBy
                                (boid.vel
                                    |> Vector2d.normalize
                                    |> Vector2d.scaleBy config.boidRad
                                )
                            |> Point2d.coordinates

                    arrows =
                        if config.showVels && isSelected then
                            arrowMapping config
                                |> List.map
                                    (\( label, color, velFunc ) ->
                                        viewArrow config color pos (velFunc boid)
                                    )

                        else
                            []

                    circleRange range =
                        Svg.circle
                            [ Svg.Attributes.cx <| pxFloat x
                            , Svg.Attributes.cy <| pxFloat y
                            , Svg.Attributes.r <| pxFloat <| range
                            , Svg.Attributes.stroke <| Color.toCssString <| boid.color
                            , Svg.Attributes.strokeOpacity <| toOpacityString boid.color
                            , Svg.Attributes.fill "none"
                            , Svg.Attributes.class "rrrrrrrrrrrrranges"
                            ]
                            []
                in
                Svg.g []
                    ([ -- ranges
                       if config.showRanges then
                        [ circleRange config.visionRange
                        , circleRange (personalSpaceRange config)
                        ]

                       else
                        []

                     -- selected lasso ring
                     , if isSelected then
                        [ Svg.circle
                            [ Svg.Attributes.cx <| pxFloat x
                            , Svg.Attributes.cy <| pxFloat y
                            , Svg.Attributes.r <| pxFloat <| (1.2 * config.boidRad)
                            , Svg.Attributes.stroke <| Color.toCssString <| boid.color
                            , Svg.Attributes.strokeOpacity <| toOpacityString boid.color
                            , Svg.Attributes.strokeDasharray "8 4"
                            , Svg.Attributes.strokeWidth "2"
                            , Svg.Attributes.fill "none"
                            , Svg.Attributes.class "sssssssssssssselected"
                            ]
                            []
                        ]

                       else
                        []

                     --beak
                     , [-- TODO fix wrapped beaks
                        --Svg.line
                        --   [ Svg.Attributes.x1 <| pxFloat x
                        --   , Svg.Attributes.y1 <| pxFloat y
                        --   , Svg.Attributes.x2 <| pxFloat beakEndpointX
                        --   , Svg.Attributes.y2 <| pxFloat beakEndpointY
                        --   , Svg.Attributes.stroke <| Color.toCssString Color.white
                        --   , Svg.Attributes.strokeWidth <| pxFloat 2
                        --   ]
                        --   []
                       ]

                     -- boid body
                     , [ Svg.circle
                            [ Svg.Attributes.cx <| pxFloat x
                            , Svg.Attributes.cy <| pxFloat y
                            , Svg.Attributes.r <| pxFloat <| config.boidRad
                            , Svg.Attributes.fill <| Color.toCssString <| boid.color
                            , Svg.Attributes.opacity <| toOpacityString <| boid.color

                            --, Svg.Attributes.opacity "0.5"
                            , Svg.Attributes.class "bbbbbbbbbbbboidbody"
                            ]
                            []
                       ]

                     -- arrows
                     , arrows
                     ]
                        |> List.concat
                    )
            )
        |> Svg.g []


viewArrow : Config -> Color -> Point2d -> Vector2d -> Svg Msg
viewArrow config color origin vec =
    let
        ( x1, y1 ) =
            Point2d.coordinates origin

        ( x2, y2 ) =
            origin
                |> Point2d.translateBy (Vector2d.scaleBy config.arrowScale vec)
                |> Point2d.coordinates
    in
    Svg.line
        [ Svg.Attributes.x1 <| pxFloat x1
        , Svg.Attributes.y1 <| pxFloat y1
        , Svg.Attributes.x2 <| pxFloat x2
        , Svg.Attributes.y2 <| pxFloat y2
        , Svg.Attributes.stroke <| Color.toCssString color
        , Svg.Attributes.strokeOpacity <| toOpacityString color
        , Svg.Attributes.strokeWidth <| pxFloat 3
        , Svg.Attributes.class "aaaaaaaaaaaaarrows"
        ]
        []


percFloat : Float -> String
percFloat val =
    String.fromFloat val ++ "%"


pxInt : Int -> String
pxInt val =
    String.fromInt val ++ "px"


pxFloat : Float -> String
pxFloat val =
    String.fromFloat val ++ "px"


subscriptions : ModelResult -> Sub Msg
subscriptions modelResult =
    case modelResult of
        Ok model ->
            Sub.batch
                [ receiveFromPort ReceivedFromPort
                , Browser.Events.onAnimationFrameDelta Tick
                ]

        Err _ ->
            Sub.none


colorGenerator : Random.Generator Color
colorGenerator =
    -- Colors from https://www.schemecolor.com/multi-color.php
    Random.uniform
        (Color.rgb255 235 102 98)
        [ Color.rgb255 247 177 114
        , Color.rgb255 247 211 126
        , Color.rgb255 130 200 129
        , Color.rgb255 29 143 148
        , Color.rgb255 32 61 133
        ]
