module ConfigSchema exposing (main)

import ConfigFormGenerator exposing (Kind(..))
import Html exposing (Html)


myConfigFields : List ( String, Kind )
myConfigFields =
    [ ( "Viewport width (px)", FloatKind "viewportWidth" )
    , ( "Viewport height (px)", FloatKind "viewportHeight" )
    , ( "Sky color", ColorKind "skyColor" )

    -- boids
    , ( "# of boids", IntKind "numBoids" )
    , ( "Boid radius (px)", FloatKind "boidRad" )
    , ( "Max speed", FloatKind "maxSpeed" )

    -- rule 0: Momentum (how quick to change steering)
    , ( "Rule 0: Momentum", SectionKind )
    , ( "Factor", FloatKind "momentumFactor" )

    -- rule 1: Cohesion (Friendly gathering at center of mass)
    , ( "Rule 1: Cohesion", SectionKind )
    , ( "Show vel", BoolKind "showCohesionVel" )
    , ( "Factor", FloatKind "cohesionFactor" )
    , ( "Range", FloatKind "cohesionRange" )
    , ( "Show range", BoolKind "showCohesionRange" )

    -- rule 2: Alignment (conformity)
    , ( "Rule 2: Alignment", SectionKind )
    , ( "Show vel", BoolKind "showAlignmentVel" )
    , ( "Factor", FloatKind "alignmentFactor" )
    , ( "Range", FloatKind "alignmentRange" )
    , ( "Show range", BoolKind "showAlignmentRange" )

    -- rule 3: Separation (personal space)
    , ( "Rule 3: Separation", SectionKind )
    , ( "Show vel", BoolKind "showSeparationVel" )
    , ( "Factor", FloatKind "separationFactor" )
    , ( "Range", FloatKind "separationRange" )
    , ( "Show range", BoolKind "showSeparationRange" )

    -- visuals
    , ( "Boid Visuals", SectionKind )
    , ( "Show sight", BoolKind "showSight" )
    , ( "Show vels", BoolKind "showVels" )

    -- config table container
    , ( "Config table container", SectionKind )
    , ( "BG color", ColorKind "configTableBgColor" )
    , ( "Border width", IntKind "configTableBorderWidth" )
    , ( "Border color", ColorKind "configTableBorderColor" )
    , ( "Padding", IntKind "configTablePadding" )

    -- config table
    , ( "Config table", SectionKind )
    , ( "Row spacing", IntKind "configRowSpacing" )
    , ( "Label highlight BG color", ColorKind "configLabelHighlightBgColor" )
    , ( "Font size", IntKind "configFontSize" )
    , ( "Input height", IntKind "configInputHeight" )
    , ( "Input width", IntKind "configInputWidth" )
    ]


main : Html msg
main =
    let
        generatedElmCode =
            ConfigFormGenerator.toFile myConfigFields

        _ =
            Debug.log generatedElmCode ""
    in
    Html.text ""