module Hasql.MTH.Codec
  ( Codec(..)
  , bool
  , bytea
  , char
  , customFindCodec
  , date
  , findCodec
  , float4
  , float8
  , genericName
  , inet
  , int2
  , int4
  , int8
  , interval
  , json
  , jsonb
  , mkCodecNullable
  , mkDecoderNullable
  , mkEncoderNullable
  , numeric
  , setNonNull
  , text
  , time
  , timestamp
  , timestamptz
  , timetz
  , uuid
  )
where

import Data.Maybe (fromMaybe)
import Hasql.MTH.Prelude
import PostgresqlSyntax.Ast

import qualified Hasql.Decoders      as Decoders
import qualified Hasql.Encoders      as Encoders
import qualified Language.Haskell.TH as TH

data Codec = Codec
  { mkEncoderNullability :: TH.Exp -> TH.Exp
  , mkDecoderNullability :: TH.Exp -> TH.Exp
  , encoder              :: TH.Exp
  , decoder              :: TH.Exp
  }

findCodec :: SimpleTypename -> Either Text Codec
findCodec = customFindCodec genericName

customFindCodec :: (Text -> Either Text Codec) -> SimpleTypename -> Either Text Codec
customFindCodec findGenericName = \case
  GenericTypeSimpleTypename a   -> genericType findGenericName a
  NumericSimpleTypename a       -> numericType a
  BitSimpleTypename{}           -> Left "Bit codec is not supported"
  CharacterSimpleTypename{}     -> pure char
  ConstDatetimeSimpleTypename a -> constDatetime a
  ConstIntervalSimpleTypename{} -> pure interval

genericType :: (Text -> Either Text Codec) -> GenericType -> Either Text Codec
genericType findGenericName (GenericType ident attributes modifiers) = case attributes of
  Just _  -> Left "Type attributes are not supported"
  Nothing -> case modifiers of
    Just _  -> Left "Type modifiers are not supported"
    Nothing -> case ident of
      QuotedIdent name   -> findGenericName name
      UnquotedIdent name -> findGenericName name

numericType :: Numeric -> Either Text Codec
numericType = \case
  IntNumeric      -> pure int4
  IntegerNumeric  -> pure int4
  SmallintNumeric -> pure int2
  BigintNumeric   -> pure int8
  RealNumeric     -> pure float4
  FloatNumeric modifiers -> case modifiers of
    Just _  -> Left "Modifier on FLOAT is not supported"
    Nothing -> pure float4
  DoublePrecisionNumeric -> pure float8
  DecimalNumeric modifiers -> case modifiers of
    Just _  -> Left "Modifiers on DECIMAL are not supported"
    Nothing -> pure numeric
  DecNumeric modifiers -> case modifiers of
    Just _  -> Left "Modifiers on DEC are not supported"
    Nothing -> pure numeric
  NumericNumeric modifiers -> case modifiers of
    Just _  -> Left "Modifiers on NUMERIC are not supported"
    Nothing -> pure numeric
  BooleanNumeric -> pure bool

constDatetime :: ConstDatetime -> Either Text Codec
constDatetime = \case
  TimestampConstDatetime _ tz -> if hasTZ tz then pure timestamptz else pure timestamp
  TimeConstDatetime _ tz      -> if hasTZ tz then pure timetz      else pure time
  where
    hasTZ = fromMaybe False

genericName :: Text -> Either Text Codec
genericName = \case
  "bool"        -> pure bool
  "int2"        -> pure int2
  "int4"        -> pure int4
  "int8"        -> pure int8
  "float4"      -> pure float4
  "float8"      -> pure float8
  "numeric"     -> pure numeric
  "char"        -> pure char
  "text"        -> pure text
  "bytea"       -> pure bytea
  "date"        -> pure date
  "timestamp"   -> pure timestamp
  "timestamptz" -> pure timestamptz
  "time"        -> pure time
  "timetz"      -> pure timetz
  "interval"    -> pure interval
  "uuid"        -> pure uuid
  "inet"        -> pure inet
  "json"        -> pure json
  "jsonb"       -> pure jsonb
  name          -> Left ("No codec exists for type: " <> name)

bool, bytea, char, date, float4, float8, inet, int2, int4, int8, interval :: Codec
json, jsonb, numeric, text, time, timestamp, timestamptz, timetz, uuid    :: Codec

bool        = mkCodecNullable 'Encoders.bool        'Decoders.bool
bytea       = mkCodecNullable 'Encoders.bytea       'Decoders.bytea
char        = mkCodecNullable 'Encoders.char        'Decoders.char
date        = mkCodecNullable 'Encoders.date        'Decoders.date
float4      = mkCodecNullable 'Encoders.float4      'Decoders.float4
float8      = mkCodecNullable 'Encoders.float8      'Decoders.float8
inet        = mkCodecNullable 'Encoders.inet        'Decoders.inet
int2        = mkCodecNullable 'Encoders.int2        'Decoders.int2
int4        = mkCodecNullable 'Encoders.int4        'Decoders.int4
int8        = mkCodecNullable 'Encoders.int8        'Decoders.int8
interval    = mkCodecNullable 'Encoders.interval    'Decoders.interval
json        = mkCodecNullable 'Encoders.json        'Decoders.json
jsonb       = mkCodecNullable 'Encoders.jsonb       'Decoders.jsonb
numeric     = mkCodecNullable 'Encoders.numeric     'Decoders.numeric
text        = mkCodecNullable 'Encoders.text        'Decoders.text
time        = mkCodecNullable 'Encoders.time        'Decoders.time
timestamp   = mkCodecNullable 'Encoders.timestamp   'Decoders.timestamp
timestamptz = mkCodecNullable 'Encoders.timestamptz 'Decoders.timestamptz
timetz      = mkCodecNullable 'Encoders.timetz      'Decoders.timetz
uuid        = mkCodecNullable 'Encoders.uuid        'Decoders.uuid

mkCodecNullable :: TH.Name -> TH.Name -> Codec
mkCodecNullable encoder decoder = Codec
  { decoder              = TH.VarE decoder
  , encoder              = TH.VarE encoder
  , mkDecoderNullability = mkDecoderNullable
  , mkEncoderNullability = mkEncoderNullable
  }

mkDecoderNonNullable, mkDecoderNullable, mkEncoderNonNullable, mkEncoderNullable :: TH.Exp -> TH.Exp
mkDecoderNonNullable = TH.AppE $ TH.VarE 'Decoders.nonNullable
mkDecoderNullable    = TH.AppE $ TH.VarE 'Decoders.nullable
mkEncoderNonNullable = TH.AppE $ TH.VarE 'Encoders.nonNullable
mkEncoderNullable    = TH.AppE $ TH.VarE 'Encoders.nullable

setNonNull :: Codec -> Codec
setNonNull Codec{..} =
  Codec
  { mkDecoderNullability = mkDecoderNonNullable
  , mkEncoderNullability = mkEncoderNonNullable
  , ..
  }
