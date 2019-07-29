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
import Element as E exposing (Element)
import Element.Background as EBackground
import Element.Border as EBorder
import Element.Events as EEvents
import Element.Font as EFont
import Element.Input as EInput
import Html exposing (Html)
import Html.Attributes
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
                , selectedBoidIndex = Nothing
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
            , vel = Vector2d.zero
            , velForCohesion = Vector2d.zero
            , velForAlignment = Vector2d.zero
            , velForSeparation = Vector2d.zero
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
            ( { model | boids = moveBoids model delta }
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
        |> mapOthers (moveBoid model.config delta)


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


moveBoid : Config -> Float -> List Boid -> Boid -> Boid
moveBoid config delta otherBoids boid =
    let
        velFromRule : Float -> (List Boid -> Vector2d) -> Vector2d
        velFromRule range ruleFunc =
            boidsInRange
                ( config.viewportWidth, config.viewportHeight )
                range
                otherBoids
                boid.pos
                |> ruleFunc

        -- cohesion (center of mass)
        velForCohesion =
            velFromRule
                config.cohesionRange
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
                config.alignmentRange
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
                config.separationRange
                (\nearbyBoids ->
                    let
                        centerOfMassOfTooCloseBoids =
                            nearbyBoids
                                |> List.map .pos
                                |> Point2d.centroid
                    in
                    case centerOfMassOfTooCloseBoids of
                        Just center ->
                            center
                                |> Vector2d.from boid.pos
                                |> Vector2d.normalize
                                |> Vector2d.scaleBy
                                    (-config.separationFactor
                                        / toFloat (List.length nearbyBoids)
                                    )

                        Nothing ->
                            Vector2d.zero
                )

        -- momentum
        velForMomentum =
            boid.vel
                |> Vector2d.scaleBy config.momentumFactor

        -- wrap it all up
        newVel =
            [ velForCohesion
            , velForSeparation
            , velForAlignment
            , velForMomentum
            ]
                |> List.foldl Vector2d.sum Vector2d.zero
                |> Vector2d.scaleBy (1 / 4)
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
    }


wrappedPoses : ( Float, Float ) -> Point2d -> List Point2d
wrappedPoses ( width, height ) pos =
    let
        ( x, y ) =
            pos
                |> Point2d.coordinates
    in
    [ pos

    --, Point2d.fromCoordinates ( x, y - height )
    --, Point2d.fromCoordinates ( x, y + height )
    --, Point2d.fromCoordinates ( x - width, y )
    --, Point2d.fromCoordinates ( x - width, y - height )
    --, Point2d.fromCoordinates ( x - width, y + height )
    --, Point2d.fromCoordinates ( x + width, y )
    --, Point2d.fromCoordinates ( x + width, y - height )
    --, Point2d.fromCoordinates ( x + width, y + height )
    ]


boidsInRange : ( Float, Float ) -> Float -> List Boid -> Point2d -> List Boid
boidsInRange viewport range boids pos =
    boids
        |> List.filterMap
            (\boid ->
                let
                    closestPos =
                        wrappedPoses viewport boid.pos
                            |> List.Extra.minimumBy
                                (Point2d.squaredDistanceFrom pos)
                            |> Maybe.withDefault boid.pos
                in
                if Point2d.squaredDistanceFrom pos closestPos <= range ^ 2 then
                    Just { boid | pos = closestPos }

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
            E.layout
                [ E.inFront <| viewConfig model
                , E.width E.fill
                , E.height E.fill
                , E.padding 20
                ]
                (E.row
                    [ E.spacing 10
                    ]
                    [ viewBoids model
                    ]
                )

        Err err ->
            Html.text err


viewConfig : Model -> Element Msg
viewConfig ({ config } as model) =
    E.el
        [ E.alignRight
        , E.padding 20
        , E.scrollbarY
        ]
        (E.el
            [ EBackground.color (colorForE config.configTableBgColor)
            , EBorder.color (colorForE config.configTableBorderColor)
            , EBorder.width config.configTableBorderWidth
            , E.scrollbarY
            , E.alignRight
            ]
            (E.column
                [ E.padding config.configTablePadding
                , E.spacing 15
                ]
                (if model.isConfigOpen then
                    [ EInput.button
                        [ E.alignRight
                        ]
                        { onPress = Just ClickedCloseConfig
                        , label =
                            E.el
                                [ EFont.underline
                                ]
                                (E.text "Close Config")
                        }
                    , ConfigForm.viewElement
                        (ConfigForm.viewOptions
                            |> ConfigForm.withRowSpacing config.configRowSpacing
                            |> ConfigForm.withLabelHighlightBgColor config.configLabelHighlightBgColor
                            |> ConfigForm.withInputWidth config.configInputWidth
                            |> ConfigForm.withInputHeight config.configInputHeight
                            |> ConfigForm.withFontSize config.configFontSize
                        )
                        Config.logics
                        model.configForm
                        |> E.map ConfigFormMsg
                    , Html.textarea
                        [ Html.Attributes.value
                            (ConfigForm.encode
                                Config.logics
                                model.config
                                |> JE.encode 2
                            )
                        ]
                        []
                        |> E.html
                        |> E.el []
                    ]

                 else
                    [ EInput.button
                        []
                        { onPress = Just ClickedOpenConfig
                        , label = E.el [ EFont.underline ] (E.text "Open Config")
                        }
                    ]
                )
            )
        )


viewBoids : Model -> Element Msg
viewBoids ({ config } as model) =
    Svg.svg
        [ Svg.Attributes.width "100%"
        , Svg.Attributes.height "100%"
        , Pointer.onMove (relativePos >> MouseMoved)
        , Pointer.onDown (relativePos >> MouseClicked)
        ]
        [ -- sky
          Svg.rect
            [ Svg.Attributes.x "0"
            , Svg.Attributes.y "0"
            , Svg.Attributes.width "100%"
            , Svg.Attributes.height "100%"
            , Svg.Attributes.fill (Color.toCssString config.skyColor)
            ]
            []
        , Svg.g []
            (model.boids
                |> Array.toIndexedList
                |> List.map
                    (viewWrappedBoid config
                        [ model.selectedBoidIndex, getHoveredBoidIndex model ]
                    )
            )
        ]
        |> E.html
        |> E.el
            [ E.width <| E.px <| round config.viewportWidth
            , E.height <| E.px <| round config.viewportHeight
            , EBorder.width 1
            , EBorder.color (E.rgb 0 0 0)
            , E.inFront
                (E.el
                    [ E.alignBottom
                    , E.alignRight
                    ]
                    (viewInspector model)
                )
            ]


relativePos : Pointer.Event -> Point2d
relativePos event =
    event.pointer.offsetPos
        |> Point2d.fromCoordinates


viewInspector : Model -> Element Msg
viewInspector model =
    case model.selectedBoidIndex of
        Just index ->
            case Array.get index model.boids of
                Just boid ->
                    let
                        rows =
                            [ ( "Cohesion Vel", vector2dToStr boid.velForCohesion |> E.text )
                            , ( "Alignment Vel", vector2dToStr boid.velForAlignment |> E.text )
                            , ( "Separation Vel", vector2dToStr boid.velForSeparation |> E.text )
                            , ( "Vel", vector2dToStr boid.vel |> E.text )
                            ]
                    in
                    E.el
                        [ EBackground.color (E.rgba 1 1 1 0.85)
                        , E.padding 15
                        ]
                        (E.table
                            [ E.spacing 5 ]
                            { data = rows
                            , columns =
                                [ { header = E.none
                                  , width = E.shrink
                                  , view = Tuple.first >> E.text
                                  }
                                , { header = E.none
                                  , width = E.shrink
                                  , view = Tuple.second
                                  }
                                ]
                            }
                        )

                Nothing ->
                    E.none

        Nothing ->
            E.none


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


viewBoid : Config -> Bool -> Boid -> Svg Msg
viewBoid config isSelected boid =
    let
        ( beakEndpointX, beakEndpointY ) =
            boid.pos
                |> Point2d.translateBy
                    (boid.vel
                        |> Vector2d.normalize
                        |> Vector2d.scaleBy config.boidRad
                    )
                |> Point2d.coordinates

        arrows =
            if config.showVels then
                Svg.g []
                    [ viewArrow Color.gray boid.pos boid.velForCohesion
                    , viewArrow Color.gray boid.pos boid.velForAlignment
                    , viewArrow Color.gray boid.pos boid.velForSeparation
                    ]

            else
                Svg.g [] []

        poses =
            [ Point2d.coordinates boid.pos
            ]

        --vels =
        --  [(config.showCohesionVel, boid.velForCohesion, Color.red)
        --  ,(config.showAlignmentVel, config.velForAlignment, Color.green)
        --  ,(config.showAlignmentVel, config.velForAlignment, Color.green)
    in
    poses
        |> List.map
            (\( x, y ) ->
                Svg.g []
                    [ if config.showSight then
                        Svg.g []
                            [ Svg.circle
                                [ Svg.Attributes.cx <| pxFloat x
                                , Svg.Attributes.cy <| pxFloat y
                                , Svg.Attributes.r <| pxFloat <| config.cohesionRange
                                , Svg.Attributes.stroke <| Color.toCssString <| boid.color
                                , Svg.Attributes.fill "none"
                                ]
                                []
                            , Svg.circle
                                [ Svg.Attributes.cx <| pxFloat x
                                , Svg.Attributes.cy <| pxFloat y
                                , Svg.Attributes.r <| pxFloat <| config.alignmentRange
                                , Svg.Attributes.stroke <| Color.toCssString <| boid.color
                                , Svg.Attributes.fill "none"
                                ]
                                []
                            , Svg.circle
                                [ Svg.Attributes.cx <| pxFloat x
                                , Svg.Attributes.cy <| pxFloat y
                                , Svg.Attributes.r <| pxFloat <| config.separationRange
                                , Svg.Attributes.stroke <| Color.toCssString <| boid.color
                                , Svg.Attributes.fill "none"
                                ]
                                []
                            ]

                      else
                        Svg.g [] []
                    , Svg.circle
                        [ Svg.Attributes.cx <| pxFloat x
                        , Svg.Attributes.cy <| pxFloat y
                        , Svg.Attributes.r <| pxFloat <| config.boidRad
                        , Svg.Attributes.fill <| Color.toCssString <| boid.color
                        ]
                        []
                    , if isSelected then
                        Svg.circle
                            [ Svg.Attributes.cx <| pxFloat x
                            , Svg.Attributes.cy <| pxFloat y
                            , Svg.Attributes.r <| pxFloat <| (1.2 * config.boidRad)
                            , Svg.Attributes.stroke <| Color.toCssString <| boid.color
                            , Svg.Attributes.strokeDasharray "8 4"
                            , Svg.Attributes.strokeWidth "2"
                            , Svg.Attributes.fill "none"
                            ]
                            []

                      else
                        Svg.g [] []
                    , Svg.line
                        [ Svg.Attributes.x1 <| pxFloat x
                        , Svg.Attributes.y1 <| pxFloat y
                        , Svg.Attributes.x2 <| pxFloat beakEndpointX
                        , Svg.Attributes.y2 <| pxFloat beakEndpointY
                        , Svg.Attributes.stroke <| Color.toCssString Color.white
                        , Svg.Attributes.strokeWidth <| pxFloat 2
                        ]
                        []
                    , arrows
                    ]
            )
        |> Svg.g []


viewArrow : Color -> Point2d -> Vector2d -> Svg Msg
viewArrow color origin vec =
    let
        ( x1, y1 ) =
            Point2d.coordinates origin

        ( x2, y2 ) =
            origin
                |> Point2d.translateBy (Vector2d.scaleBy 10 vec)
                |> Point2d.coordinates
    in
    Svg.line
        [ Svg.Attributes.x1 <| pxFloat x1
        , Svg.Attributes.y1 <| pxFloat y1
        , Svg.Attributes.x2 <| pxFloat x2
        , Svg.Attributes.y2 <| pxFloat y2
        , Svg.Attributes.stroke <| Color.toCssString color
        , Svg.Attributes.strokeWidth <| pxFloat 3
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


colorForE : Color -> E.Color
colorForE color =
    color
        |> Color.toRgba
        |> (\{ red, green, blue, alpha } ->
                E.rgba red green blue alpha
           )


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