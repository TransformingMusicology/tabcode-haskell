-- TabCode - A parser for the Tabcode lute tablature language
--
-- Copyright (C) 2016 Richard Lewis, Goldsmiths' College
-- Author: Richard Lewis <richard.lewis@gold.ac.uk>

-- This file is part of TabCode

-- TabCode is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- TabCode is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with TabCode.  If not, see <http://www.gnu.org/licenses/>.

{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module TabCode.MEI
  ( TabWordsToMEI
  , mei
  , defaultDoc
  , module TabCode.MEI.Elements
  , module TabCode.MEI.Types
  , (<>) ) where

import           Data.Monoid                   ((<>))
import           Data.Text                     (pack)
import qualified Data.Vector                   as V
import           Data.Vector                   (Vector)
import           TabCode
import           TabCode.MEI.Elements
import           TabCode.MEI.Types
import           Text.Parsec.Prim
import           Text.Parsec.Combinator
import           Text.ParserCombinators.Parsec

instance (Monad m) => Stream (Vector a) m a where
  uncons v | V.null v  = return Nothing
           | otherwise = return $ Just (V.unsafeHead v, V.unsafeTail v)

-- Now let's consider trying HXT again for the conversion. That way,
-- you get an (partial) MEI parser for "free".

type TabWordsToMEI = Parsec (Vector TabWord) () MEI

defaultDoc :: [MEI] -> MEI
defaultDoc staves = MEIMusic noMEIAttrs [body]
  where
    body    = MEIBody    noMEIAttrs [mdiv]
    mdiv    = MEIMDiv    noMEIAttrs [parts]
    parts   = MEIParts   noMEIAttrs [part]
    part    = MEIPart    noMEIAttrs [section]
    section = MEISection noMEIAttrs staves

mei :: ([MEI] -> MEI) -> String -> TabCode -> Either ParseError MEI
mei doc source (TabCode rls tws) = parse (containers doc) source tws

containers :: ([MEI] -> MEI) -> TabWordsToMEI
containers doc = do
  s <- staff
  return $ doc $ [s]

staff :: TabWordsToMEI
staff = do
  staffDef <- meter
  chords   <- many1 $ tuple <|> chord <|> rest
  return $ MEIStaff noMEIAttrs $ staffDef : chords

tuple :: TabWordsToMEI
tuple = do
  c  <- chordCompound
  cs <- many chordNoRS
  return $ MEITuple ( atNum 3 <> atNumbase 2 ) $ c : cs

chord :: TabWordsToMEI
chord = tokenPrim show updatePos getChord
  where
    getChord ch@(Chord l c r ns) =
      Just $ MEIChord ( atDur <$:> r ) $ ( elRhythmSign <$:> r ) <> ( concat $ (elNote rls) <$> ns )
    getChord _ = Nothing
    rls = []

chordCompound :: TabWordsToMEI
chordCompound = tokenPrim show updatePos getChord
  where
    getChord ch@(Chord l c r@(Just (RhythmSign _ Compound _ _)) ns) =
      Just $ MEIChord ( atDur <$:> r ) $ ( elRhythmSign <$:> r ) <> ( concat $ (elNote rls) <$> ns )
    getChord _ = Nothing
    rls = []

chordNoRS :: TabWordsToMEI
chordNoRS = tokenPrim show updatePos getChord
  where
    getChord ch@(Chord l c Nothing ns) =
      -- FIXME We need the duration from the previous chord here
      Just $ MEIChord noMEIAttrs $ ( concat $ (elNote rls) <$> ns )
    getChord _ = Nothing
    rls = []

rest :: TabWordsToMEI
rest = tokenPrim show updatePos getRest
  where
    getRest re@(Rest l c rs) = Just $ MEIRest noMEIAttrs []
    getRest _                = Nothing

meter :: TabWordsToMEI
meter = tokenPrim show updatePos getMeter
  where
    getMeter me@(Meter l c m) = case m of
      (SingleMeterSign PerfectMajor)
        -> Just $ MEIStaffDef ( atProlation 3 <> atTempus 3 ) [ MEIMensur ( atSign 'O' <> atDot True ) [] ]
      (SingleMeterSign PerfectMinor)
        -> Just $ MEIStaffDef ( atProlation 3 <> atTempus 2 ) [ MEIMensur ( atSign 'O' <> atDot False ) [] ]
      (SingleMeterSign ImperfectMajor)
        -> Just $ MEIStaffDef ( atProlation 2 <> atTempus 3 ) [ MEIMensur ( atSign 'C' <> atDot True ) [] ]
      (SingleMeterSign ImperfectMinor)
        -> Just $ MEIStaffDef ( atProlation 2 <> atTempus 2 ) [ MEIMensur ( atSign 'C' <> atDot False ) [] ]
      (SingleMeterSign HalfPerfectMajor)
        -> Just $ MEIStaffDef ( atProlation 3 <> atTempus 3 <> atSlash 1 ) [ MEIMensur ( atSign 'O' <> atDot True <> atCut 1 ) [] ]
      (SingleMeterSign HalfPerfectMinor)
        -> Just $ MEIStaffDef ( atProlation 3 <> atTempus 2 <> atSlash 1 ) [ MEIMensur ( atSign 'O' <> atDot False <> atCut 1 ) [] ]
      (SingleMeterSign HalfImperfectMajor)
        -> Just $ MEIStaffDef ( atProlation 2 <> atTempus 3 <> atSlash 1 ) [ MEIMensur ( atSign 'C' <> atDot True <> atCut 1 ) [] ]
      (SingleMeterSign HalfImperfectMinor)
        -> Just $ MEIStaffDef ( atProlation 2 <> atTempus 2 <> atSlash 1 ) [ MEIMensur ( atSign 'C' <> atDot False <> atCut 1 ) [] ]
      (VerticalMeterSign (Beats n) (Beats b))
        -> Just $ MEIStaffDef ( atNumDef n <> atNumbaseDef b ) [ MEIMeterSig ( atCount n <> atUnit b ) [] ]
      (SingleMeterSign (Beats 3))
        -> Just $ MEIStaffDef ( atTempus 3 ) []
      _
        -> Just $ XMLComment $ pack $ " tc2mei: Un-implemented mensuration sign: " ++ (show m) ++ " "

    getMeter _ = Nothing


updatePos :: SourcePos -> TabWord -> Vector TabWord -> SourcePos
updatePos pos _ v
  | V.null v  = pos
  | otherwise = setSourceLine (setSourceColumn pos (twColumn tok)) (twLine tok)
  where
    tok = V.head v