-- | A class of things that can be procedurally generated from random numbers generated by the
-- Twofish random number generator. The "Control.Monad.Random.Class" monad is re-exported, providing
-- the 'Control.Monad.Random.Class.getRandomR', 'Control.Monad.Random.Class.getRandom',
-- 'Control.Monad.Random.Class.getRandomRs', and 'Control.Monad.Random.Class.getRandoms' functions
-- which you can use to define instances of the 'arbitrary' function for your procedurally generated
-- data types.
module ProcGen.Arbitrary
  ( Arbitrary(..), onArbitrary, onRandFloat,
    TFRandT(..), TFRand, evalTFRandSeed, evalTFRandIO, arbTFRandSeed, arbTFRandIO,
    evalTFRand, runTFRand, evalTFRandT, runTFRandT,
    System.Random.TF.Init.initTFGen,
    module Control.Monad.Random.Class,
  ) where

import           ProcGen.Types

import           Control.Monad
import           Control.Monad.Trans
import           Control.Monad.Random.Class
import           Control.Monad.Trans.Random.Lazy

import           Data.Functor.Identity
import           Data.Word

import           System.Random.TF
import           System.Random.TF.Init

----------------------------------------------------------------------------------------------------

-- | This is a function which defines a common interface for procedurally generating values from an
-- arbitrary random number generator, where the random number generator is defined to be an instance
-- of the 'Control.Monad.Random.Class.MonadRandom' class. Minimal complete definition is just
-- the 'arbitrary' function.
class Arbitrary a where
  -- | Produce a single random value in a function type @m@ which must be a member of the
  -- 'Control.Monad.Random.Class.MonadRandom' class.
  arbitrary :: (Functor m, Monad m, Applicative m, MonadRandom m) => m a
  -- | You can provide your own list-generating version of 'arbtirary', but the default behavior of
  -- this function, if you don't define your own, is to simply generate between 1 and 10 'arbitrary'
  -- values.
  arbitraryList :: (Functor m, Monad m, Applicative m, MonadRandom m) => (Int, Int) -> m [a]
  arbitraryList = getRandomR >=> flip replicateM arbitrary

-- | Often you obtain a random value and then immediately perform some transformation on it by using
-- 'fmap' or 'Control.Monad.liftM'. This function allows you to specify the transformation as a
-- parameter without using 'fmap' or 'Control.Monad.liftM'.
onArbitrary :: (MonadRandom m, Arbitrary a) => (a -> b) -> m b
onArbitrary f = f <$> arbitrary

onRandFloat :: MonadRandom m => (ProcGenFloat -> a) -> m a
onRandFloat f = f <$> getRandom

----------------------------------------------------------------------------------------------------

-- | A simple default pure random number generator based on the Twofish pseudo-random number
-- generator provided by the 'System.Random.TF.Gen'. This function type instantiates the
-- 'Control.Monad.Random.Class.MonadRandom' class so that you can use this to evaluate an instance
-- of 'arbitrary'. 
newtype TFRandT m a = TFRandT { unwrapTFRandT :: RandT TFGen m a }
  deriving (Functor, Applicative, Monad)

type TFRand a = TFRandT Identity a

instance Monad m => MonadRandom (TFRandT m) where
  getRandomR  = TFRandT . getRandomR
  getRandom   = TFRandT getRandom
  getRandomRs = TFRandT . getRandomRs
  getRandoms  = TFRandT getRandoms

instance MonadTrans TFRandT where { lift = TFRandT . lift; }

-- | Evaluate a 'TFRand' function using a Twofish pseudo-random seed composed of any four 64-bit
-- unsigned integers. The pure random result is returned.
evalTFRandSeed :: Word64 -> Word64 -> Word64 -> Word64 -> TFRand a -> a
evalTFRandSeed s0 s1 s2 s3 f = evalTFRand f $ seedTFGen (s0,s1,s2,s3)

-- | Evaluate the 'runTFRandSeed' function using entropy pulled from the operating system as a seed
-- value. This will produce a different random result every time it is run.
evalTFRandIO :: TFRand a -> IO a
evalTFRandIO f = evalTFRand f <$> initTFGen

-- | Similar to 'evalTFRandSeed', except instead of supplying just any 'TFRand' function for
-- evaluation, use the 'arbitrary' function intance that has been defined for the the data type @a@
-- to produce a result @a@.
arbTFRandSeed :: Arbitrary a => Word64 -> Word64 -> Word64 -> Word64 -> a
arbTFRandSeed s0 s1 s2 s3 = evalTFRandSeed s0 s1 s2 s3 arbitrary

-- | Similar to 'evalTFRandSeed', except instead of supplying just any 'TFRand' function for
-- evaluation, use the 'arbitrary' function intance that has been defined for the the data type @a@
-- to produce a result @a@.
arbTFRandIO :: Arbitrary a => IO a
arbTFRandIO = evalTFRandIO arbitrary

-- | Run a 'TFRand' function with an already-existing Twofish generator. This function is not very
-- useful unless you choose to use the 'System.Random.split' function to evaluate a nested 'TFRand'
-- function within another 'TFRand' function. If you simply want to generate a random value, it is
-- better to use 'runTFRandSeed' or 'runTFRandIO'.
evalTFRand :: TFRand a -> TFGen -> a
evalTFRand (TFRandT f) = evalRand f

-- | Like 'evalTFRand' but does not disgard the Twofish random generator, allowing you to re-use it
-- elsewhere.
runTFRand :: TFRand a -> TFGen -> (a, TFGen)
runTFRand (TFRandT f) = runRand f

evalTFRandT :: Monad m => TFRandT m a -> TFGen -> m a
evalTFRandT (TFRandT f) = evalRandT f

runTFRandT :: Monad m => TFRandT m a -> TFGen -> m (a, TFGen)
runTFRandT (TFRandT f) = runRandT f
