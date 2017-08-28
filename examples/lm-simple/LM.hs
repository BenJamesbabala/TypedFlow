{-# LANGUAGE AllowAmbiguousTypes #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UnicodeSyntax #-}
module Aggr where

import TypedFlow

first :: (t2 -> t1) -> (t2, t) -> (t1, t)
first f (a,b) = (f a, b)

predict :: forall (outSize::Nat) (vocSize::Nat) batchSize. KnownNat outSize => KnownNat vocSize => KnownNat batchSize => Model '[21,batchSize] Int32 '[batchSize] Int32
predict input gold = do
  embs <- parameter "embs" embeddingInitializer
  lstm1 <- parameter "w1" lstmInitializer
  drp <- mkDropout (DropProb 0.1)
  rdrp <- mkDropout (DropProb 0.1)
  w <- parameter "dense" denseInitialiser
  (_sFi,predictions) <-
    rnn (timeDistribute (embedding @9 @vocSize embs)
          .-.
          timeDistribute drp
          .-.
          (onState (first rdrp) (lstm @50 lstm1)))
        (I (zeros,zeros) :* Unit) input
  categorical ((dense @outSize w) (last0 predictions)) gold


main :: IO ()
main = do
  generateFile "lm.py" (compile (defaultOptions {maxGradientNorm = Just 1}) (predict @5 @11 @512))
  putStrLn "done!"

(|>) :: ∀ a b. a -> b -> (a, b)
(|>) = (,)
infixr |>


{-> main


<interactive>:57:1: error:
    • Variable not in scope: main
    • Perhaps you meant ‘min’ (imported from Prelude)
-}



