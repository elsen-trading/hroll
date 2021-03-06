{-# LANGUAGE BangPatterns #-}
module Covariance (
  Covariance(..),
  mkCovariance,
  updateCovariance,
  getCovariance,
) where

-- This is an implementation of a rolling covariance. It rests on the
-- implementation of a well-chosen accumulation function for our accumulating
-- deque.
--
-- From the definition of covariance it's not immediately obvious how
-- to calculate it in a rolling fashion:
-- cov xs ys = sum (zipWith (\x y -> (x - x0) * (y - y0))) / (n - 1)
--   where
--     n  = min (length xs) (length ys)
--     x0 = mean xs
--     y0 = mean ys
--     mean xs = sum xs / length xs
--
-- However, if we expand this definition we can see how this formula can be
-- expanded into several sums -- which we do know how to calculate in a
-- rolling fashion!
-- Ignoring the outer length constant for the moment,
-- cov [a,b,c,d] [x,y,z,w]
-- let m = mean [a,b,c,d] and n = mean[x,y,z,w]
-- -> (a - m) * (x - n)
--  + (b - m) * (y - n)
--  + (c - m) * (z - n)
--  + (d - m) * (w - n)
--
-- -> a*x + m*n - a*n - x*m
--  + b*y + m*n - b*n - y*m
--  + c*z + m*n - c*n - z*m
--  + d*w + m*n - d*n - w*m
--
-- -> (a*x + b*y + c*z + d*w) -- call this the cross sum
--  + len*m*n                 -- product of means
--  - n*(a + b + c + d)       -- mean ys * sum xs
--  - m*(x + y + z + w)       -- mean xs * sum ys
--
-- Noting that mean xs == sum xs / length xs we can further simplify
-- -> zipWith (*) xs ys
--  + len * mean xs * mean ys
--  - mean ys * sum xs
--  - mean xs * sum ys
--
-- -> zipWith (*) xs ys
--  + sum xs * sum ys / len
--  - sum ys / len * sum xs
--  - sum xs / len * sum ys
--
-- Terms cancel, giving the simple formula
-- -> zipWith (*) xs ys - (sum xs * sum ys / len)
--
-- So the problem of rolling covariance boils down to calculating
-- a) rolling cross sum
-- b) rolling sum of xs
-- c) rolling sum of ys
-- d) rolling length
--
-- So easy!

data Covariance = CovarianceAccumulator
  { x     :: {-#UNPACK#-} !Double
  , y     :: {-#UNPACK#-} !Double
  , cross :: {-#UNPACK#-} !Double -- cross sum, basically zipWith (*) xs ys
  , sumx  :: {-#UNPACK#-} !Double -- sum xs
  , sumy  :: {-#UNPACK#-} !Double -- sum ys
  , len   :: {-#UNPACK#-} !Int    -- length
  }

instance Show Covariance where
  show = show . getCovariance

mkCovariance :: Double -> Double -> Covariance
mkCovariance x y = CovarianceAccumulator
  { x     = x
  , y     = y
  , cross = x*y
  , sumx  = x
  , sumy  = y
  , len   = 1
  }

updateCovariance :: Covariance -> Covariance -> Covariance
updateCovariance
  (CovarianceAccumulator x0 y0 cross0 sumx0 sumy0 len0)
  (CovarianceAccumulator x1 y1 cross1 sumx1 sumy1 len1)
  = CovarianceAccumulator
    { x     = x0 -- doesn't matter, we just want the accumulator
    , y     = y0 -- doesn't matter, we just want the accumulator
    , cross = cross0 + cross1
    , sumx  = sumx0  + sumx1
    , sumy  = sumy0  + sumy1
    , len   = len0   + len1
    }

-- Extract the covariance from the sum.
getCovariance :: Covariance -> Double
getCovariance (CovarianceAccumulator _ _ cross sumx sumy len_) = let
  len = fromIntegral len_
  -- Unfortunately this is apparently prone to numerical stability issues. Cf.
  -- https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Na.C3.AFve_algorithm
  -- http://math.stackexchange.com/questions/702981/catastrophic-cancellation
  num = cross - sumx*sumy/len
  den = fromIntegral (len_ - 1)
  in num / den

getX :: Covariance -> Double
getX (CovarianceAccumulator x _ _ _ _ _) = x

getY :: Covariance -> Double
getY (CovarianceAccumulator _ y _ _ _ _) = y

