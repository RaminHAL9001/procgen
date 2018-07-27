-- | A typeclass providing a consistent interface to various objects which can be marshalled to an
-- immutable unboxed Vector representation. Objects of this type should be stored in memory as
-- vectors and should be observed by being converted to lazy data types.
module ProcGen.VectorBuilder where

import           Control.Lens
import           Control.Monad.Reader
import           Control.Monad.Primitive
import           Control.Monad.State.Strict
import           Control.Monad.ST

import qualified Data.Vector.Generic.Mutable.Base  as MVec
import qualified Data.Vector.Generic.Mutable       as MVec
import qualified Data.Vector.Unboxed               as UVec

----------------------------------------------------------------------------------------------------

-- | A function type for buliding mutable 'UVec.Vector's with a function that uses a cursor to move
-- around withtin a mutable 'Vec.Vector'.
newtype BuildContiguous vec elem m a
  = BuildContiguous
    { unwrapBuildContiguous :: StateT (BuildContiguousState vec elem m) m a
    }
  deriving (Functor, Applicative, Monad)

instance MonadTrans (BuildContiguous vec elem) where
  lift = BuildContiguous . lift

instance Monad m => MonadState (BuildContiguousState vec elem m) (BuildContiguous vec elem m) where
  state = BuildContiguous . state

data BuildContiguousState vec elem m
  = BuildContiguousState
    { theBuilderCursor :: !Int
    , theBuilderVector :: !(vec (PrimState m) elem)
    }

-- | Given an initial vector size, allocate an 'MVec.STVector' of that size and then evaluate a
-- 'BuildContiguous' function to populate the 'MVec.STVector'. When 'BuildContiguous' function
-- evaluation completes, freeze the 'MVec.STVector' to a 'UVec.Vector' and eliminate the monad
-- entirely, becoming a pure function.
runBuildContiguousST
  :: (UVec.Unbox elem)
  => Int -> (forall s . BuildContiguous UVec.MVector elem (ST s) void) -> UVec.Vector elem
runBuildContiguousST size build = UVec.create $ do
  vec <- MVec.new size
  evalStateT (unwrapBuildContiguous $ build >> use builderVector) BuildContiguousState
    { theBuilderCursor = 0
    , theBuilderVector = vec
    }

-- | A lens to access the cursor at which 'builderPutElem' and 'builderGetElem' will put or get an
-- element value.
builderCursor
  :: (PrimMonad m, MVec.MVector vec elem)
  => Lens' (BuildContiguousState vec elem m) Int
builderCursor = lens theBuilderCursor $ \ a b -> a{ theBuilderCursor = b }

-- | A lens to access the vector that is currently being filled with @elem@ values.
builderVector
  :: (PrimMonad m, MVec.MVector vec elem)
  => Lens' (BuildContiguousState vec elem m) (vec (PrimState m) elem)
builderVector = lens theBuilderVector $ \ a b -> a{ theBuilderVector = b }

-- | Take the value of an @elem@ at the current 'builderCursor' in the 'builderVector'.
builderGetElem :: (PrimMonad m, MVec.MVector vec elem) => BuildContiguous vec elem m elem
builderGetElem = MVec.read <$> use builderVector <*> use builderCursor >>= lift

-- | Reposition the 'builderCursor'. Returns the value of the 'builderCursor' as it was set before the
-- @('Int' -> 'Int')@ function was applied.
modifyCursor :: (PrimMonad m, MVec.MVector vec elem) => (Int -> Int) -> BuildContiguous vec elem m Int
modifyCursor = (<*) (use builderCursor) . (builderCursor %=)

-- | Get the current length of the vector allocation size being built.
maxBuildLength :: (PrimMonad m, MVec.MVector vec elem) => BuildContiguous vec elem m Int
maxBuildLength = MVec.length <$> use builderVector

-- | Force re-allocation of the vector using 'MVec.grow' or 'MVec.take', depending on whether the
-- updated size value computed by the given @('Int' -> 'Int')@ function is greater or less than the
-- current vector size.
resizeVector
  :: (PrimMonad m, MVec.MVector vec elem)
  => (Int -> Int)
  -> BuildContiguous vec elem m ()
resizeVector f = do
  oldsize <- maxBuildLength
  let newsize = f oldsize
  if oldsize == newsize then return () else
    if oldsize < newsize
     then MVec.unsafeGrow <$> use builderVector <*> pure newsize >>= lift >>= (builderVector .=)
     else MVec.take newsize <$> use builderVector >>= (builderVector .=)

-- | Place an @elem@ value at the current 'builderCursor', and then increment the 'builderCursor'.
buildStep :: (PrimMonad m, MVec.MVector vec elem) => elem -> BuildContiguous vec elem m ()
buildStep e = do
  MVec.write <$> use builderVector <*> use builderCursor <*> pure e >>= lift
  builderCursor += 1

-- | Get the @elem@ value at the current 'builderCursor', and then increment the 'builderCursor'.
buildTake1 :: (PrimMonad m, MVec.MVector vec elem) => BuildContiguous vec elem m elem
buildTake1 =
  (MVec.read <$> use builderVector <*> use builderCursor >>= lift) <*
  (builderCursor += 1)

-- | The 'buildTake1' value applied 2 times to return a double, and thus advancing the
-- 'builderCursor' by 2 indicies as well.
buildTake2 :: (PrimMonad m, MVec.MVector vec elem) => BuildContiguous vec elem m (elem, elem)
buildTake2 = (,) <$> buildTake1 <*> buildTake1

-- | The 'buildTake1' value applied 3 times to return a tripple, and thus advancing the
-- 'builderCursor' by 3 indicies as well.
buildTake3 :: (PrimMonad m, MVec.MVector vec elem) => BuildContiguous vec elem m (elem, elem, elem)
buildTake3 = (,,) <$> buildTake1 <*> buildTake1 <*> buildTake1

-- | The 'buildTake1' value applied 4 times to return a tripple, and thus advancing the
-- 'builderCursor' by 4 indicies as well.
buildTake4
  :: (PrimMonad m, MVec.MVector vec elem)
  => BuildContiguous vec elem m (elem, elem, elem, elem)
buildTake4 = (,,,) <$> buildTake1 <*> buildTake1 <*> buildTake1 <*> buildTake1

-- | The 'buildTake1' value applied 5 times to return a tripple, and thus advancing the
-- 'builderCursor' by 5 indicies as well.
buildTake5
  :: (PrimMonad m, MVec.MVector vec elem)
  => BuildContiguous vec elem m (elem, elem, elem, elem, elem)
buildTake5 = (,,,,) <$> buildTake1 <*> buildTake1 <*> buildTake1 <*> buildTake1 <*> buildTake1

-- | The 'buildTake1' value applied 5 times to return a tripple, and thus advancing the
-- 'builderCursor' by 5 indicies as well.
buildTake6
  :: (PrimMonad m, MVec.MVector vec elem)
  => BuildContiguous vec elem m (elem, elem, elem, elem, elem, elem)
buildTake6 = (,,,,,) <$> buildTake1 <*> buildTake1 <*>
  buildTake1 <*> buildTake1 <*> buildTake1 <*> buildTake1

-- | A range building function. This function is required as a parameter by 'buildMapRange',
-- 'buildMapRangeM', 'buildScanRange', 'buildScanRangeM', 'buildFoldRange', and
-- 'buildFoldRangeM'. Functions which take a range constructor pass two values: the cursor,
-- and the length of the array. You then return a tuple with the range you want to scan over.
type MakeRange = Int -> Int -> (Int, Int)

-- | A 'MakeRange' function that ranges the entire 'builderVector'.
wholeVector :: MakeRange
wholeVector _ len = rangeFence 0 len

-- | A 'MakeRange' function that ranges all elements in the 'builderVector' up to but not including
-- the current 'builderCursor'.
allBeforeCursor :: MakeRange
allBeforeCursor i _ = rangeFence 0 i

-- | A 'MakeRange' function that ranges all elements from the current 'builderCursor' (including the
-- element under the cursor) all the way to the final element in the 'MVec.Vector'.
allAfterCursor :: MakeRange
allAfterCursor = rangeFence

-- | Takes a start and end index value and constructs a range that includes the start index value,
-- and runs up until but does not include, the end index value. The word "fence" here refers to
-- "fencepost bugs" in which a programmer accesses an array in which indicies begin at zero, and the
-- index accessed is equal to the length of the array which is beyond the final fencepost. Use this
-- function if you are coding an algorithm in which you might make make that mistake.
rangeFence :: MakeRange
rangeFence a b = (a, b-1)

-- | Map elements over a range, updating them as you go.
buildMapRange
  :: (PrimMonad m, MVec.MVector vec elem)
  => MakeRange
  -> (Int -> elem -> elem)
  -> BuildContiguous vec elem m ()
buildMapRange makeRange f = buildMapRangeM makeRange (\ i -> pure . f i)

-- | A version of 'buildMapRange' that takes a monadic mapping function.
buildMapRangeM
  :: (PrimMonad m, MVec.MVector vec elem)
  => MakeRange
  -> (Int -> elem -> BuildContiguous vec elem m elem)
  -> BuildContiguous vec elem m ()
buildMapRangeM makeRange f = do
  vec   <- use builderVector
  range <- makeRange <$> use builderCursor <*> maxBuildLength
  forM_ range $ \ i -> lift (MVec.read vec i) >>= f i >>= lift . MVec.write vec i

-- | Scan over a range of @elem@ values, updating a stateful value with each @elem@, and returning
-- an optional new value to write back to the 'builderVector'.
buildScanRange
  :: (PrimMonad m, MVec.MVector vec elem)
  => MakeRange -> st
  -> (Int -> elem -> st -> (Maybe elem, st))
  -> BuildContiguous vec elem m st
buildScanRange makeRange st f = buildScanRangeM makeRange st (\ i e -> pure . f i e)

-- | A version of 'buildScanRange' that takes a monadic scanning function.
buildScanRangeM
  :: (PrimMonad m, MVec.MVector vec elem)
  => MakeRange -> st
  -> (Int -> elem -> st -> BuildContiguous vec elem m (Maybe elem, st))
  -> BuildContiguous vec elem m st
buildScanRangeM makeRange st f = do
  vec <- use builderVector
  makeRange <$> use builderCursor <*> maxBuildLength >>=
    foldM (\ st i -> lift (MVec.read vec i) >>= flip (f i) st >>= \ (update, st) ->
      maybe (return ()) (lift . MVec.write vec i) update >> return st) st

-- | Like 'buildScanRangeM' but does not update any elements.
buildFoldRangeM
  :: (PrimMonad m, MVec.MVector vec elem)
  => MakeRange -> st
  -> (Int -> elem -> st -> BuildContiguous vec elem m st)
  -> BuildContiguous vec elem m st
buildFoldRangeM makeRange st f = do
  vec <- use builderVector
  makeRange <$> use builderCursor <*> maxBuildLength >>=
    foldM (\ st i -> lift (MVec.read vec i) >>= flip (f i) st) st

----------------------------------------------------------------------------------------------------

