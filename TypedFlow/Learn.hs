{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeInType #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UnicodeSyntax #-}

module TypedFlow.Learn where

import TypedFlow.Types
import TypedFlow.TF
import qualified Prelude (Float)
import Prelude (($),return,Maybe(..),id)
import Text.PrettyPrint.Compact (text)
import Data.Monoid hiding (Last)
import GHC.TypeLits (KnownNat)
import Control.Monad.State (modify)



-- crossEntropy :: Tensor '[n,bs] Float32 -> Tensor '[n,bs] Float32 -> Tensor '[bs] Float32
-- crossEntropy y_ y = negate (reduceSum0 (y_ ⊙ log y))

  -- (- t * log(y) - (1 - t) * log(1 - y))

binaryCrossEntropy :: KnownNat bs => Tensor '[bs] Float32 -> Tensor '[bs] Float32 -> Tensor '[bs] Float32
binaryCrossEntropy t y = negate (t ⊙ log y) ⊝ (ones ⊝ t) ⊙ log (ones ⊝ y)

--------------------------------
-- Model maker.

type Batch s batchSize = Tensor (s++'[batchSize])

-- | First type argument is the number of classes.
-- @categorical logits gold@
-- return (prediction, accuraccy, loss)
-- accuracy and prediction are averaged over the batch.
categorical :: forall nCat bs. KnownNat nCat => Model '[nCat,bs] Float32 '[bs] Int32
categorical logits' y = do
  logits <- assign logits'
  let y_ = argmax0 logits
      modelY = y_
  correctPrediction <- assign (equal y_ y)
  modelAccuracy <- assign (reduceMeanAll (cast @Float32 correctPrediction))
  modelLoss <- assign (reduceMeanAll (softmaxCrossEntropyWithLogits (oneHot0 y) logits))
  return ModelOutput{..}

-- | First type argument is the number of classes.
-- @categoricalDistribution logits gold@
-- return (prediction, accuraccy, loss)
-- accuracy and prediction are averaged over the batch.
categoricalDistribution :: forall nCat bs. Model '[nCat,bs] Float32 '[nCat,bs] Float32
categoricalDistribution logits' y = do
  logits <- assign logits'
  let y_ = softmax0 logits
      modelY = y_
  correctPrediction <- assign (equal (argmax0 @'B32 logits) (argmax0 y))
  modelAccuracy <- assign (reduceMeanAll (cast @Float32 correctPrediction))
  modelLoss <- assign (reduceMeanAll (softmaxCrossEntropyWithLogits y logits))
  return ModelOutput{..}

timedCategorical :: forall len nCat bs. KnownNat nCat => KnownNat bs => KnownNat len => Model '[len,nCat,bs] Float32 '[len,bs] Int32
timedCategorical logits' y = do
  logits <- assign logits'
  let y_ = (argmax1 logits)
      modelY = y_
  correctPrediction <- assign (equal (argmax1 logits) y)
  modelAccuracy <- assign (reduceMeanAll (flatten2 (cast @Float32 correctPrediction)))
  crossEntropies <- zipWithT softmaxCrossEntropyWithLogits (oneHot1 y) logits
  modelLoss <- assign (reduceMeanAll crossEntropies)
  return ModelOutput{..}
  -- TODO: use sentence length to mask "useless" loss?

data ModelOutput s t = ModelOutput {modelY :: T s t -- ^ prediction
                                   ,modelLoss :: Scalar Float32
                                   ,modelAccuracy :: Scalar Float32
                                   }
-- | (input value, gold value) ↦ (prediction, accuracy, loss)
type Model input tIn output tOut = T input tIn -> T output tOut -> Gen (ModelOutput output tOut)


binary :: forall bs. (KnownNat bs) => Model '[bs] Float32 '[bs] Int32
binary score y = do
  sigy_ <- assign (sigmoid score)
  let y_ = cast @Int32 (round sigy_)
      modelY = y_
  correctPrediction <- assign (equal y_ y)
  modelAccuracy <- assign (reduceMeanAll (cast @Float32 correctPrediction))
  modelLoss <- assign (reduceMeanAll (binaryCrossEntropy (cast @Float32 y) sigy_))
  return ModelOutput{..}

data Options = Options {maxGradientNorm :: Maybe Prelude.Float}

defaultOptions :: Options
defaultOptions = Options {maxGradientNorm = Nothing}

compile :: (KnownShape input, KnownTyp tIn, KnownShape output, KnownTyp tOut) =>
           Options ->
           Model input tIn output tOut  -> Gen ()
compile Options{..} model = do
  gen (text "import tensorflow as tf")
  genFun "mkModel" [] $ do
    x <- placeholder "x"
    y <- placeholder "y"
    trainingPhasePlaceholder <- placeholder "training_phase"
    modify $ \GState{..} -> GState{genTrainingPlaceholder = trainingPhasePlaceholder,..}
    ModelOutput{..} <- model x y
    y_ <- assign modelY
    loss <- assign modelLoss
    accuracy <- assign modelAccuracy
    params <- getParameters
    gradients <- newVar
    let clipping = case maxGradientNorm of
                     Nothing -> id
                     Just clip -> clipByGlobalNorm clip
    gradients <-- clipping (grad modelLoss params)
    gen (text "return " <> dict [("training_phase", fromTensor trainingPhasePlaceholder)
                                ,("x",fromTensor x)
                                ,("y",fromTensor y)
                                ,("y_",fromTensor y_)
                                ,("accuracy",fromTensor accuracy)
                                ,("loss",fromTensor loss)
                                ,("params",params)
                                ,("gradients",gradients)])
