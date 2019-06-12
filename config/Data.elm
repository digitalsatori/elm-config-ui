module Main exposing (main)

import Dict exposing (Dict)
import Egg.ConfigFormGenerator exposing (..)
import Html exposing (Html)


sample : List ( String, ( String, Kind ) )
sample =
    [ ( "Header font size", ( "headerFontSize", IntKind ) )
    , ( "Header string", ( "headerString", StringKind ) )
    , ( "Subheader font size (float)", ( "subheaderFontSize", FloatKind ) )
    , ( "Subheader string", ( "subheaderString", StringKind ) )
    , ( "Subheader color", ( "subheaderColor", ColorKind ) )
    , ( "Subheader padding", ( "subheaderPadding", IntKind ) )
    , ( "Config table BG color", ( "configTableBgColor", ColorKind ) )
    , ( "Config table spacing", ( "configTableSpacing", IntKind ) )
    , ( "Config table padding", ( "configTablePadding", IntKind ) )
    , ( "Config table border width", ( "configTableBorderWidth", IntKind ) )
    , ( "Config table border color", ( "configTableBorderColor", ColorKind ) )
    , ( "Config table label highlight BG color", ( "configLabelHighlightBgColor", ColorKind ) )
    , ( "Config font size", ( "configFontSize", IntKind ) )
    , ( "Config input height", ( "configInputHeight", IntKind ) )
    ]


main : Html msg
main =
    let
        generatedElmCode =
            toFile sample

        _ =
            Debug.log generatedElmCode ""
    in
    Html.text ""
