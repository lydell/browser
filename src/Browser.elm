module Browser exposing
  ( staticPage
  , sandbox
  , embed
  , fullscreen
  , Page
  , Env
  , focus, blur, DomError(..)
  , scrollIntoView
  , getScroll
  , setScrollTop, setScrollBottom
  , setScrollLeft, setScrollRight
  , onDocument
  , onWindow
  , preventDefaultOnDocument
  , preventDefaultOnWindow
  )

{-| This module helps you set up an Elm `Program` with functions like
[`sandbox`](#sandbox) and [`fullscreen`](#fullscreen).

It also has a bunch of miscellaneous helpers for global event listeners and
for focusing and scrolling DOM nodes.


# Static Pages
@docs staticPage


# Dynamic Pages
@docs sandbox, embed, fullscreen, Page, Env


# DOM Stuff

## Focus
@docs focus, blur, DomError

## Scroll
@docs scrollIntoView, getScroll, setScrollTop, setScrollBottom, setScrollLeft, setScrollRight


# Global Events
@docs onDocument, onWindow, preventDefaultOnDocument, preventDefaultOnWindow


-}



import Dict
import Browser.Events as E
import Browser.Navigation.Manager as Navigation
import Debugger.Main
import Elm.Kernel.Browser
import Json.Decode as Decode
import Process
import Task exposing (Task)
import Url.Parser as Url
import Html exposing (Html)



-- PROGRAMS


{-| Show some static HTML.

    import Browser exposing (staticPage)
    import Html exposing (text)

    main =
      staticPage (text "Hello!")

Using `staticPage` means that all user input is ignored. For example, the
events generated by button presses are sent to a black hole of nothingness,
never to be heard from again. Try out [`sandbox`](#sandbox) to make an
interactive Elm program!
-}
staticPage : Html msg -> Program () () msg
staticPage =
  Elm.Kernel.Browser.staticPage


{-| Create a “sandboxed” program that cannot communicate with the outside
world.

This is great for learning the basics of [The Elm Architecture][tea]. You can
see sandboxes in action in tho following examples:

  - [Buttons](http://elm-lang.org/examples/buttons)
  - [Text Field](http://elm-lang.org/examples/field)
  - [Checkboxes](http://elm-lang.org/examples/checkboxes)

Those are nice, but **I very highly recommend reading [this guide][guide]
straight through** to really learn how Elm works. Understanding the
fundamentals actually pays off in this language!

[tea]: https://guide.elm-lang.org/architecture/
[guide]: https://guide.elm-lang.org/
-}
sandbox :
  { init : model
  , view : model -> Html msg
  , update : msg -> model -> model
  }
  -> Program () model msg
sandbox { init, view, update } =
  embed
    { init = \_ -> ( init, Cmd.none )
    , view = view
    , update = \msg model -> ( update msg model, Cmd.none )
    , subscriptions = \_ -> Sub.none
    }


{-| Create a program that can be embedded in a larger JavaScript project.
This is a great low-risk way of introducing Elm into your existing work, and
lots of companies that use Elm started with this approach!

Unlike a [`sandbox`](#sandbox), an “embedded” program can talk to the outside
world in a couple ways:

  - `Cmd` &mdash; you can “command” the Elm runtime to do stuff, like HTTP.
  - `Sub` &mdash` you can “subscribe” to event sources, like clock ticks.
  - `flags` &mdash; JavaScript can pass in data when starting the Elm program
  - `ports` &mdash; set up a client-server relationship with JavaScript

As you read [the guide][guide] you will run into a bunch of examples of `embed`
in [this section][fx]. You can learn more about flags and ports in [the interop
section][interop].

[guide]: https://guide.elm-lang.org/
[fx]: https://guide.elm-lang.org/architecture/effects/
[interop]: https://guide.elm-lang.org/interop/
-}
embed :
  { init : flags -> (model, Cmd msg)
  , view : model -> Html msg
  , update : msg -> model -> ( model, Cmd msg )
  , subscriptions : model -> Sub msg
  }
  -> Program flags model msg
embed =
  Elm.Kernel.Browser.embed


{-| Create a fullscreen Elm program. This expands the functionality of
[`embed`](#embed) in two important ways:

  1. The `view` gives you control over the `<title>` and `<body>`.

  2. The `onNavigation` field lets you capture [`Url`][url] changes. This
  allows you to create single-page apps (SPAs) with the help of the
  [`Browser.Navigation`](Browser-Navigation) module.

[url]: http://package.elm-lang.org/packages/elm-lang/url/latest/Url-Parser#Url

You also get an [`Env`](#Env) value on `init` which gives a bit more
information about the host browser.

Here are some example usages of `fullscreen` programs:

  - [RealWorld example app](https://github.com/rtfeldman/elm-spa-example)
  - [Elm’s package website](https://github.com/elm-lang/package.elm-lang.org)

These are quite advanced Elm programs, so be sure to go through [the
guide](https://guide.elm-lang.org/) first to get a solid conceptual foundation
before diving in! If you start reading a calculus book from page 314, it might
seem confusing. Same here!
-}
fullscreen :
  { init : Env flags -> (model, Cmd msg)
  , view : model -> Page msg
  , update : msg -> model -> ( model, Cmd msg )
  , onNavigation : Maybe (Url.Url -> msg)
  , subscriptions : model -> Sub msg
  }
  -> Program flags model msg
fullscreen impl =
  Elm.Kernel.Browser.fullscreen
    { init = \{ flags, url } -> impl.init (Env flags (unsafeToUrl url))
    , view = impl.view
    , update = impl.update
    , subscriptions =
        case impl.onNavigation of
          Nothing ->
            impl.subscriptions

          Just toMsg ->
            Navigation.addListen (toMsg << unsafeToUrl) impl.subscriptions
    }


{-| This data specifies the `<title>` and all of the nodes that should go in
the `<body>`. This means you can update the title as your application changes.
Maybe your "single-page app" navigates to a "different page", maybe a calendar
app shows an accurate date in the title, etc.

> **Note about CSS:** This looks similar to an `<html>` document, but this is
> not the place to manage CSS assets. If you want to work with CSS, there are
> a couple ways:
>
> 1. Use the [`rtfeldman/elm-css`][elm-css] package to get all of the features
> of CSS without any CSS files. You can add all the styles you need in your
> `view` function, and there is no need to worry about class names matching.
>
> 2. Compile your Elm code to JavaScript with `elm make --output=elm.js` and
> then make your own HTML file that loads `elm.js` and the CSS file you want.
> With this approach, it does not matter where the CSS comes from. Write it
> by hand. Generate it. Whatever you want to do.
>
> 3. If you need to change `<link>` tags dynamically, you can send messages
> out a port to do it in JavaScript.
>
> The bigger point here is that loading assets involves touching the `<head>`
> as an implementation detail of browsers, but that does not mean it should be
> the responsibility of the `view` function in Elm. So we do it differently!

[elm-css]: /rtfeldman/elm-css/latest/
-}
type alias Page msg =
  { title : String
  , body : List (Html msg)
  }



-- ENVIRONMENT


{-| When you initialize an Elm program, you get some information about the
environment. Right now this contains:

  - `flags` &mdash; This holds data that is passed in from JavaScript.

  - `url` &mdash; The initial [`Url`][url] of the page. If you are creating a
  single-page app (SPA) you can use the [`Url.Parser`][parser] module to parse
  a URL into useful data and figure out what to show on screen. If you are not
  making a single-page app, you can ignore this!

[url]: http://package.elm-lang.org/packages/elm-lang/url/latest/Url-Parser#Url
[parser]: http://package.elm-lang.org/packages/elm-lang/url/latest/Url-Parser
-}
type alias Env flags =
  { flags : flags
  , url : Url.Url
  }


unsafeToUrl : String -> Url.Url
unsafeToUrl string =
  case Url.toUrl string of
    Nothing ->
      Elm.Kernel.Browser.invalidUrl string

    Just url ->
      url



-- GLOBAL EVENTS


{-| Subscribe to events on `document`. Here are some examples:

  - [Keyboard](https://github.com/elm-lang/browser/blob/master/hints/keyboard.md)
  - [Mouse]()

**Note:** This uses [passive][] event handlers, enabling optimizations for events
like `touchstart` and `touchmove`.

[passive]: https://github.com/WICG/EventListenerOptions/blob/gh-pages/explainer.md
-}
onDocument : String -> Decode.Decoder msg -> Sub msg
onDocument name decoder =
  E.on E.Document True name (Decode.map addFalse decoder)


{-| Subscribe to events on `window`. Here are some examples:

  - [Scroll]()
  - [Resize]()

**Note:** This uses [passive][] event handlers, enabling optimizations for events
like `scroll` and `wheel`.

[passive]: https://github.com/WICG/EventListenerOptions/blob/gh-pages/explainer.md
-}
onWindow : String -> Decode.Decoder msg -> Sub msg
onWindow name decoder =
  E.on E.Window True name (Decode.map addFalse decoder)


{-| Subscribe to events on `document` and conditionally prevent the default
behavior. For example, pressing `SPACE` causes a “page down” normally, and
maybe you want it to do something different.

**Note:** This disables the [passive][] optimization, causing a performance
degredation for events like `touchstart` and `touchmove`.

[passive]: https://github.com/WICG/EventListenerOptions/blob/gh-pages/explainer.md
-}
preventDefaultOnDocument : String -> Decode.Decoder (msg, Bool) -> Sub msg
preventDefaultOnDocument =
  E.on E.Document False


{-| Subscribe to events on `window` and conditionally prevent the default
behavior.

**Note:** This disables the [passive][] optimization, causing a performance
degredation for events like `scroll` and `wheel`.

[passive]: https://github.com/WICG/EventListenerOptions/blob/gh-pages/explainer.md
-}
preventDefaultOnWindow : String -> Decode.Decoder (msg, Bool) -> Sub msg
preventDefaultOnWindow =
  E.on E.Window False


addFalse : msg -> (msg, Bool)
addFalse msg =
  (msg, False)



-- DOM STUFF


{-| All the DOM functions here look nodes up by their `id`. If you ask for an
`id` that is not in the DOM, you will get this error.
-}
type DomError = NotFound String



-- FOCUS


{-| Find a DOM node by `id` and focus on it. So if you wanted to focus a node
like `<input type="text" id="search-box">` you could say:

    import Browser
    import Task

    type Msg = NoOp

    focusSearchBox : Cmd Msg
    focusSearchBox =
      Task.attempt (\_ -> NoOp) (Browser.focus "search-box")

Notice that this code ignores the possibility that `search-box` is not used
as an `id` by any node, failing silently in that case. It would be better to
log the failure with whatever error reporting software you use.
-}
focus : String -> Task DomError ()
focus =
  Elm.Kernel.Browser.call "focus"


{-| Find a DOM node by `id` and make it lose focus. So if you wanted a node
like `<input type="text" id="search-box">` to lose focus you could say:

    import Browser
    import Task

    type Msg = NoOp

    unfocusSearchBox : Cmd Msg
    unfocusSearchBox =
      Task.attempt (\_ -> NoOp) (Browser.blur "search-box")
-}
blur : String -> Task DomError ()
blur =
  Elm.Kernel.Browser.call "blur"




-- SCROLL


{-| Find a DOM node by `id` and scroll it into view. Maybe we want to scroll
to arbitrary headers in a long document? We could define a `scrollTo`
function like this:

    import Browser
    import Task

    type Msg = NoOp

    scrollTo : String -> Cmd Msg
    scrollTo id =
      Task.attempt (\_ -> NoOp) (Browser.scrollIntoView id)
-}
scrollIntoView : String -> Task DomError ()
scrollIntoView =
  Elm.Kernel.Browser.call "scrollIntoView"


{-| Find a DOM node by `id` and get its `scrollLeft` and `scrollTop` values.
-}
getScroll : String -> Task DomError ( Float, Float )
getScroll =
  Elm.Kernel.Browser.getScroll


{-| Find a DOM node by `id` and set the scroll offset from the top. If we want
to scroll to the top, we can say:

    import Browser
    import Task

    type Msg = NoOp

    scrollToTop : String -> Cmd Msg
    scrollToTop id =
      Task.attempt (\_ -> NoOp) (Browser.setScrollTop id 0)

So the offset from the top is zero. If we said `setScrollTop id 100` the
content would be scrolled down 100 pixels.
-}
setScrollTop : String -> Float -> Task DomError ()
setScrollTop =
  Elm.Kernel.Browser.setPositiveScroll "scrollTop"


{-| Same as [`setScrollTop`](#setScrollTop), but it sets the scroll offset
from the bottom. So saying `setScrollBottom id 0` scrolls all the way down.
That can be useful in a chat room where messages keep appearing.

If you said `setScrollBottom id 200`, it is like you scrolled all the way to
the bottom and then scrolled up 200 pixels.
-}
setScrollBottom : String -> Float -> Task DomError ()
setScrollBottom =
  Elm.Kernel.Browser.setNegativeScroll "scrollTop" "scrollHeight"


{-| Same as [`setScrollTop`](#setScrollTop), but it sets the horizontal scroll
offset from the left side.
-}
setScrollLeft : String -> Float -> Task DomError ()
setScrollLeft =
  Elm.Kernel.Browser.setPositiveScroll "scrollLeft"


{-| Same as [`setScrollTop`](#setScrollTop), but it sets the horizontal scroll
offset from the right side.
-}
setScrollRight : String -> Float -> Task DomError ()
setScrollRight =
  Elm.Kernel.Browser.setNegativeScroll "scrollLeft" "scrollWidth"

