{-# LANGUAGE ConstraintKinds #-}
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
{-# LANGUAGE OverloadedStrings #-}

module TypedFlow.Types where

import Text.PrettyPrint.Compact hiding (All,Last)
import GHC.TypeLits
import Data.Proxy
import Control.Monad.State
import Data.Char (toLower)
-- import GHC.Prim (unsafeCoerce#)
import Data.Kind (Type,Constraint)
type DOC = Doc ()

type family (++) xs ys where
   '[] ++  xs       = xs
   (x ': xs) ++ ys       = x ': (xs ++ ys)

type family Last xs where
  Last '[x] = x
  Last (x ': xs) = Last xs

type family Init xs where
  Init '[x] = '[]
  Init (x ': xs) = x ': Init xs

-- Some proofs.

-- initLast' :: forall s k. ((Init s ++ '[Last s]) ~ s => k) -> k
-- initLast' k = unsafeCoerce# k -- why not?

initLast' :: forall s k. SShape s -> ((Init s ++ '[Last s]) ~ s => k) -> k
initLast' Nil _ = error "initLast': does not hold on empty lists"
initLast' (Cons _ Nil) k = k
initLast' (Cons _ (Cons y ys)) k = initLast' (Cons y ys) (k)

initLast :: forall s k. KnownShape s => ((Init s ++ '[Last s]) ~ s => k) -> k
initLast = initLast' @s shapeSing


splitApp' :: forall ys xs k. PeanoLen xs -> ((Take (PeanoLength xs) (xs ++ ys) ~ xs,
                                              Drop (PeanoLength xs) (xs ++ ys) ~ ys) => k) -> k
splitApp' LZ k = k
splitApp' (LS n) k = splitApp' @ys n k

splitApp :: forall xs ys k. KnownLen xs => ((Take (PeanoLength xs) (xs ++ ys) ~ xs,
                                             Drop (PeanoLength xs) (xs ++ ys) ~ ys) => k) -> k
splitApp = splitApp' @ys (shapePeanoLen @xs)

type family Length xs where
  Length '[] = 0
  Length (x ': xs) = 1 + Length xs

type family Reverse' xs ys where
  Reverse' '[] ys = ys
  Reverse' (x ': xs) ys = Reverse' xs (x ': ys )

type family Reverse xs where
  Reverse xs = Reverse' xs '[]

newtype V (n::Nat) a = V [a]
  deriving (Functor, Foldable, Traversable)

instance KnownNat n => Applicative (V n) where
  pure = V . replicate (fromIntegral (natVal (Proxy @n)))
  V fs <*> V xs = V (zipWith ($) fs xs)

data V' (n::Nat) a where
  VZ :: V' 0 a
  VS :: a -> V' n a -> V' (1+n) a

-- From: https://www.cs.ox.ac.uk/projects/utgp/school/andres.pdf
data NP f (xs :: [k]) where
  Unit :: NP f '[]
  (:*) :: f x -> NP f xs -> NP f (x ': xs)
newtype I a = I a
type HList = NP I


type family All (c :: k -> Constraint) (xs :: [k]) :: Constraint where
  All c '[] = ()
  All c (x ': xs) = (c x, All c xs)

-- | Flip at type level
newtype F g t s = F (g s t)

-- | Heterogeneous tensor vector with the same kind of elements
type HTV t = NP (F T t)

hmap :: (forall x. f x -> g x) -> NP f xs -> NP g xs
hmap _ Unit = Unit
hmap f (x :* xs) = f x :* hmap f xs


happ :: NP f xs -> NP f ys -> NP f (xs ++ ys)
happ Unit xs = xs
happ (x :* xs) ys = x :* (happ xs ys)

hsplit' :: SPeano n -> NP f xs -> (NP f (Take n xs), NP f (Drop n xs))
hsplit' SZero xs = (Unit,xs)
hsplit' (SSucc _n) Unit = (Unit,Unit)
hsplit' (SSucc n) (x :* xs) = case hsplit' n xs of
  (l,r) -> (x :* l,r)

hsplit :: forall xs ys f. KnownLen xs => NP f (xs++ys) -> (NP f xs, NP f ys)
hsplit xys = splitApp @xs @ys (hsplit' (shapePeano @xs) xys)

hsnoc :: NP f xs -> f x -> NP f (xs ++ '[x])
hsnoc xs x = happ xs (x :* Unit)

infixr 5 :*

data Peano = Zero | Succ Peano

type Dim0 = 'Zero
type Dim1 = 'Succ Dim0
type Dim2 = 'Succ Dim1
type Dim3 = 'Succ Dim2

class KnownPeano n where peanoInt :: Integer
instance KnownPeano 'Zero where peanoInt = 0
instance KnownPeano n => KnownPeano ('Succ n) where peanoInt = 1 + (peanoInt @n)

data SPeano n where
  SZero :: SPeano 'Zero
  SSucc :: SPeano n -> SPeano ('Succ n)

data Vec (n::Peano) a where
  VNil  :: Vec 'Zero a
  VCons :: a -> Vec n a -> Vec ('Succ n) a

vecToList :: Vec n a -> [a]
vecToList VNil = []
vecToList (VCons x xs) = x : vecToList xs

-- type family App n (xs :: Vec n a) ys where
--    App 'Zero 'VNil  xs            =  xs
--    App ('Succ n) ('VCons x xs) ys =  x ': App n xs ys

type family Take n xs where
   Take 'Zero xs            =  '[]
   Take ('Succ n) '[] =  '[]
   Take ('Succ n) (x ': xs) =  x ': Take n xs

type family Drop n xs where
   Drop 'Zero xs            =  xs
   Drop ('Succ n) '[]            =  '[]
   Drop ('Succ n) (x ': xs) =  Drop n xs

type family At n xs where
  At 'Zero (x ': xs) = x
  At ('Succ n) (x ': xs) = At n xs

data Kind = Float | Int | Bool deriving Show
data NBits = B32 | B64 | B1 deriving Show
data Typ = Typ Kind NBits

type Float32 = 'Typ 'Float 'B32
type Int32 = 'Typ 'Int 'B32
type Int64 = 'Typ 'Int 'B64
type TFBool = 'Typ 'Bool 'B1

instance Show Typ where
  show (Typ Bool _)= "tf.bool"
  show (Typ k l) = "tf." ++ map toLower (show k) ++ drop 1 (show l)

showTyp :: forall t. KnownTyp t => DOC
showTyp = text (show (typVal @t))

type Shape = [Nat]

type UntypedExpression = DOC
data T (shape :: Shape) (t :: Typ) = T {fromTensor :: UntypedExpression}

data SNat (n :: Nat) where
  SNat :: KnownNat n => Proxy n -> SNat n

data SShape s where
  Nil :: SShape '[]
  Cons :: SNat x -> SShape xs -> SShape (x ': xs)

class KnownLen s => KnownShape s where
  shapeSing :: SShape s

instance KnownShape '[] where
  shapeSing = Nil

instance (KnownNat x, KnownShape xs) => KnownShape (x ': xs) where
  shapeSing = Cons (SNat Proxy) shapeSing

class KnownTyp t where
  typVal :: Typ
class KnownBits t where
  bitsVal :: NBits

instance KnownBits 'B32 where bitsVal = B32
instance KnownBits 'B64 where bitsVal = B64
instance (KnownBits l, KnownKind k) => KnownTyp ('Typ k l) where
  typVal = Typ (kindVal @k) (bitsVal @l)

class KnownKind t where
  kindVal :: Kind

instance KnownKind 'Float where
  kindVal = Float

instance KnownKind 'Int where
  kindVal = Int

data PeanoLen s where
  LZ :: PeanoLen '[]
  LS :: forall x xs. PeanoLen xs -> PeanoLen (x ': xs)

type family PeanoLength xs :: Peano where
  PeanoLength '[] = 'Zero
  PeanoLength (x ': xs) = 'Succ (PeanoLength xs)

class KnownLen s where
  shapeLen :: Integer
  shapePeano :: SPeano (PeanoLength s)
  shapePeanoLen :: PeanoLen s

instance KnownLen '[] where
  shapeLen = 0
  shapePeano = SZero
  shapePeanoLen = LZ
  
instance KnownLen xs => KnownLen (x ': xs) where
  shapeLen = 1 Prelude.+ shapeLen @ xs
  shapePeano = SSucc (shapePeano @xs)
  shapePeanoLen = LS (shapePeanoLen @xs)


getShape :: ∀s. KnownShape s=> SShape s
getShape = shapeSing

shapeToList' :: SShape s -> [Integer]
shapeToList' Nil = []
shapeToList' (Cons (SNat x) xs) = natVal x : shapeToList' xs

shapeToList :: ∀(s::Shape). KnownShape s => [Integer]
shapeToList = shapeToList' (getShape @ s)

showShape :: ∀ (s :: Shape). KnownShape s => DOC
showShape = list (map (showDim' "None") (reverse (shapeToList @ s)))

-- | Show a shape, but "None" is replaced by "-1"
showShapeMinus :: ∀ (s :: Shape). KnownShape s => DOC
showShapeMinus = list (map (showDim' "-1") (reverse (shapeToList @ s)))

showShapeLen :: ∀ (s::Shape). KnownLen s => DOC
showShapeLen = (text . show) (shapeLen @ s)

rememberNat :: SNat n -> (KnownNat n => r) -> r
rememberNat (SNat _) k = k

type None = 514229 --  fibonnaci prime.
-- type None = 0 - 1 -- GHC does not like negative Nats.
-- Using a maybe type would be a RPITA.

showDim' :: String -> Integer -> DOC
showDim' none n = text (if n == 514229 then none else show n)

showDimM :: forall n. KnownNat n => DOC
showDimM = showDim' "-1" (natVal (Proxy @ n))

showDim :: forall n. KnownNat n => DOC
showDim = showDim' "None" (natVal (Proxy @ n))

str :: Show a => a -> DOC
str = text . show

--------------------------------
-- Generation Effects

data GState = GState {nextVar :: Integer,
                      genText :: DOC}
newtype Gen x = Gen {fromGen :: State GState x} deriving (Monad, MonadState GState, Functor, Applicative)

newVar :: Gen DOC
newVar = do
  n <- gets nextVar
  modify $ \GState{..} -> GState {nextVar=nextVar+1,..}
  return (text "var" <> integer n)

gen :: DOC -> Gen ()
gen s = modify $ \GState{..} -> GState {genText=genText $$ s,..}

setGen :: DOC -> Gen ()
setGen d = modify $ \GState{..} -> GState {genText=d,..}

withDOC :: forall a. (DOC -> DOC) -> Gen a -> Gen a
withDOC f g = do
  before <- gets genText
  setGen mempty
  x <- g
  after <- gets genText
  setGen (before $$ f after)
  return x

type Tensor shape = T shape

-----------------------------------------
-- Generation helpers


(<--) :: DOC -> UntypedExpression -> Gen ()
x <-- y = gen (x <> text "=" <>  y)

tuple :: [DOC] -> DOC
tuple = parens . sep . punctuate comma

funcall :: String -> [DOC] -> DOC
funcall = funcall' . text

funcall' :: DOC -> [DOC] -> DOC
funcall' f args =
  let as = sep (punctuate comma args)
      open = f <> "("
  in (open <|> (flush open <> text "  ")) <> as <> ")"

binOp :: ∀ s1 s2 s3 t1 t2 t3. String -> Tensor s1 t1 -> Tensor s2 t2 -> Tensor s3 t3
binOp op (T x) (T y) = T (funcall op [ x , y])

unOp :: ∀ s1 s2 t1 t2. String -> Tensor s1 t1 -> Tensor s2 t2
unOp op (T x) = T (funcall op [x])

assign :: ∀s t. (T s t) -> Gen (T s t)
assign (T x) = do
  v <- newVar
  v <-- x
  return (T v)

genFun :: forall b. String -> [DOC] -> Gen b -> Gen b
genFun name args body = do
  gen (text "def " <> text name <> tuple args <> text ":")
  withDOC (\b -> text "  " <> b) body

lambda :: (T s t -> T s' t') -> Gen UntypedExpression
lambda f = do
  v <- newVar
  let T body = f (T v)
  return (text "lambda " <> v <> ": " <> body)

generate :: Gen () -> String
generate s = renderWith (Options 92 (const id)) (genText (execState (fromGen s) (GState {nextVar = 0, genText = mempty})))

named :: String -> DOC -> DOC
named fname x = text (fname <> "=") <> x
