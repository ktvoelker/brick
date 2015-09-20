-- | Basic types used by this library.
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE RankNTypes #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Brick.Types
  ( -- * The Widget type
    Widget(..)

    -- * Location types and lenses
  , Location(..)
  , locL
  , TerminalLocation(..)
  , CursorLocation(..)
  , cursorLocationL
  , cursorLocationNameL

  -- * Viewports
  , Viewport(..)
  , ViewportType(..)
  , vpSize
  , vpTop
  , vpLeft

  -- * Event-handling types
  , EventM
  , Next
  , HandleEvent(..)
  , handleEventLensed

  -- * Rendering infrastructure
  , RenderM
  , getContext

  -- ** The rendering context
  , Context(ctxAttrName, availWidth, availHeight, ctxBorderStyle, ctxAttrMap)
  , attrL
  , availWidthL
  , availHeightL
  , ctxAttrMapL
  , ctxAttrNameL
  , ctxBorderStyleL

  -- ** Rendering results
  , Result(..)
  , lookupAttrName

  -- ** Rendering result lenses
  , imageL
  , cursorsL
  , visibilityRequestsL

  -- ** Visibility requests
  , VisibilityRequest(..)
  , vrPositionL
  , vrSizeL

  -- * Making lenses
  , suffixLenses

  -- * Miscellaneous
  , Size(..)
  , Padding(..)
  , Direction(..)
  , Name(..)

  )
where

import Control.Lens (_1, _2, to, (^.), (&), (.~), Lens')
import Data.Monoid (Monoid(..))
import Control.Monad.Trans.State.Lazy
import Control.Monad.Trans.Reader
import Graphics.Vty (Event, Image, emptyImage, Attr)
import Data.Default (Default(..))
import Data.Functor.Contravariant
import qualified Data.Map as M

import Brick.Types.TH
import Brick.Types.Internal
import Brick.AttrMap (AttrName, attrMapLookup)

-- | The type of padding.
data Padding = Pad Int
             -- ^ Pad by the specified number of rows or columns.
             | Max
             -- ^ Pad up to the number of available rows or columns.

-- | The class of types that provide some basic event-handling.
class HandleEvent a where
    -- | Handle a Vty event
    handleEvent :: Event -> a -> EventM a

-- | A convenience function for handling events intended for values
-- that are targets of lenses in your application state. This function
-- obtains the target value of the specified lens, invokes 'handleEvent'
-- on it, and stores the resulting transformed value back in the state
-- using the lens.
handleEventLensed :: (HandleEvent b)
                  => a
                  -- ^ The state value.
                  -> Lens' a b
                  -- ^ The lens to use to extract and store the target
                  -- of the event.
                  -> Event
                  -- ^ The event to handle.
                  -> EventM a
handleEventLensed v target ev = do
    newB <- handleEvent ev (v^.target)
    return $ v & target .~ newB

-- | The monad in which event handlers run. Although it may be tempting
-- to dig into the reader value yourself, just use
-- 'Brick.Main.lookupViewport'.
type EventM a = ReaderT (M.Map Name Viewport) (StateT EventState IO) a

-- | Widget growth policies. These policies communicate to layout
-- algorithms how a widget uses space when being rendered. These
-- policies influence rendering order and space allocation in the box
-- layout algorithm.
data Size = Fixed
          -- ^ Fixed widgets take up the same amount of space no matter
          -- how much they are given (non-greedy).
          | Greedy
          -- ^ Greedy widgets take up all the space they are given.
          deriving (Show, Eq, Ord, Bounded)

-- | The type of widgets.
data Widget =
    Widget { hSize :: Size
           -- ^ This widget's horizontal growth policy
           , vSize :: Size
           -- ^ This widget's vertical growth policy
           , render :: RenderM Result
           -- ^ This widget's rendering function
           }

-- | The type of the rendering monad. This monad is used by the
-- library's rendering routines to manage rendering state and
-- communicate rendering parameters to widgets' rendering functions.
type RenderM a = ReaderT Context (State RenderState) a

-- | The type of result returned by a widget's rendering function. The
-- result provides the image, cursor positions, and visibility requests
-- that resulted from the rendering process.
data Result =
    Result { image :: Image
           -- ^ The final rendered image for a widget
           , cursors :: [CursorLocation]
           -- ^ The list of reported cursor positions for the
           -- application to choose from
           , visibilityRequests :: [VisibilityRequest]
           -- ^ The list of visibility requests made by widgets rendered
           -- while rendering this one (used by viewports)
           }
           deriving Show

instance Default Result where
    def = Result emptyImage [] []

-- | Get the current rendering context.
getContext :: RenderM Context
getContext = ask

suffixLenses ''Context
suffixLenses ''Result

-- | The rendering context's current drawing attribute.
attrL :: (Contravariant f, Functor f) => (Attr -> f Attr) -> Context -> f Context
attrL = to (\c -> attrMapLookup (c^.ctxAttrNameL) (c^.ctxAttrMapL))

instance TerminalLocation CursorLocation where
    columnL = cursorLocationL._1
    column = column . cursorLocation
    rowL = cursorLocationL._2
    row = row . cursorLocation

-- | Given an attribute name, obtain the attribute for the attribute
-- name by consulting the context's attribute map.
lookupAttrName :: AttrName -> RenderM Attr
lookupAttrName n = do
    c <- getContext
    return $ attrMapLookup n (c^.ctxAttrMapL)
