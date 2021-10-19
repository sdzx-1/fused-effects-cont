{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}

module Cont where

import Control.Algebra
import Control.Carrier.Error.Either
import Control.Carrier.State.Strict
import Control.Concurrent
import Control.Effect.Labelled
import Control.Monad
import Control.Monad.IO.Class
import Control.Monad.Identity
import Control.Monad.Trans.Class
import Data.Functor.Const
import Data.Functor.Identity
import Data.Kind
import System.IO

newtype ContT r m a = ContT {runContT :: (m a -> m r) -> m r}

evalContT :: (Monad m) => (m a -> m r) -> ContT r m a -> m r
evalContT f m = runContT m f

instance Functor m => Functor (ContT r m) where
  fmap f m = ContT $ \c -> runContT m (c . fmap f)

instance Applicative m => Applicative (ContT r m) where
  pure x = ContT ($ pure x)
  f <*> v = ContT $ \c -> runContT f $ \g -> runContT v (\tmp -> c (g <*> tmp))

-- never del this
-- res <- runContT <$> (k <$> x)
-- res c
instance (Monad m) => Monad (ContT r m) where
  m >>= k = ContT $ \c -> runContT m ((<$>) k >=> (($ c) . runContT))

instance MonadTrans (ContT r) where
  lift m = ContT $ \g -> g m

instance MonadIO m => MonadIO (ContT r m) where
  liftIO io = ContT $ \c -> c (liftIO io)

callCC1 :: ((m a -> ContT r m b) -> ContT r m a) -> ContT r m a
callCC1 f = ContT $ \c -> runContT (f (\x -> ContT $ \_ -> c x)) c

callCC :: Applicative m => ((a -> ContT r m b) -> ContT r m a) -> ContT r m a
callCC f = ContT $ \c -> runContT (f (\x -> ContT $ \_ -> c (pure x))) c

-- type CC r s a = ContT r (StateC s (StateC String IO)) a

data CallCC r (m :: Type -> Type) a where
  CallCC :: ((m a -> m b) -> m a) -> CallCC r m a

cc :: HasLabelled CallCC (CallCC r) sig m => ((m a -> m b) -> m a) -> m a
cc = sendLabelled @CallCC . CallCC

instance Algebra sig m => Algebra (CallCC r :+: sig) (ContT r m) where
  alg hdl sig ctx = case sig of
    L (CallCC f) -> undefined
    R other -> ContT $ \g -> do
      ContT bv <- thread ((pure . join) ~<~ hdl) other (pure @(ContT r m) ctx)
      bv g

type CC r s a = ContT r (ErrorC String IO) a

-- val :: CC () Int Int
val :: CC Int Int Int
-- val :: ErrorC String IO Int
val = do
  catchError @String (throwError "finish1") (\_ -> return ())
  catchError @String (throwError "finish3") (\_ -> return ())
  catchError @String (throwError "finish4") (\_ -> return ())
  catchError @String (throwError "finish5") (\_ -> return ())
  return 1

-- r <- callCC (\next -> let x = next x in return x)
-- when (tv > 5) $ throwError "finish" -- catchError @String (throwError "finish") (\_ -> return ())

-- runVal = evalContT (>>= print) $ runError @String $ runState @Int 0 $ val
runVal = runError @String $ evalContT id val

-- runVal = runError @String val
