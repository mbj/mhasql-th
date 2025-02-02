module Hasql.MTH
  ( foldStatement
  , maybeStatement
  , resultlessStatement
  , rowsAffectedStatement
  , singletonStatement
  , uncheckedSql
  , uncheckedSqlFile
  , vectorStatement
  )
where

import Hasql.MTH.Prelude
import Language.Haskell.TH.Quote
import Language.Haskell.TH.Syntax

import qualified Data.Text                  as Text
import qualified Data.Text.Encoding         as Text
import qualified Hasql.MTH.Construction.Exp as Exp
import qualified Hasql.MTH.Extraction.Exp   as ExpExtraction
import qualified PostgresqlSyntax.Ast       as Ast
import qualified PostgresqlSyntax.Parsing   as Parsing

-- * Helpers

exp :: (String -> Q Exp) -> QuasiQuoter
exp =
  let unsupported _ = fail "Unsupported"
   in \exp' -> QuasiQuoter exp' unsupported unsupported unsupported

expParser :: (Text -> Either Text Exp) -> QuasiQuoter
expParser parser =
  exp $ \inputString -> either (fail . Text.unpack) pure $ parser $ fromString inputString

expPreparableStmtAstParser :: (Text -> Ast.PreparableStmt -> Either Text Exp) -> QuasiQuoter
expPreparableStmtAstParser parser =
  expParser $ \input -> do
    ast <- first fromString $ Parsing.run (Parsing.atEnd Parsing.preparableStmt) input
    parser input ast

-- $setup
-- >>> import Data.Int
-- >>> import Data.Vector
-- >>> import Hasql.Statement
-- >>> import Hasql.MTH.Codec
-- >>> foldStatement'         = foldStatement         findCodec
-- >>> maybeStatement'        = maybeStatement        findCodec
-- >>> resultlessStatement'   = resultlessStatement   findCodec
-- >>> rowsAffectedStatement' = rowsAffectedStatement findCodec
-- >>> singletonStatement'    = singletonStatement    findCodec
-- >>> vectorStatement'       = vectorStatement       findCodec

-- * Statement

-- |
-- @
-- :: `Statement` params row
-- @
--
-- Statement producing exactly one result row.
--
-- Will cause the running session to fail with the
-- `Hasql.Session.UnexpectedAmountOfRows` error if it's any other.
--
-- === __Examples__
--
-- >>> :t [singletonStatement'|select 1 :: int2|]
-- ...
-- ... :: Statement () (Maybe Int16)
--
-- >>> :{
--   :t [singletonStatement'|
--        insert into "user" (email, name)
--        values ($1 :: text, $2 :: text)
--        returning id :: int4
--        |]
-- :}
-- ...
-- ... :: Statement (Maybe Text, Maybe Text) (Maybe Int32)
--
-- Incorrect SQL:
--
-- >>> :t [singletonStatement'|elect 1|]
-- ...
--   |
-- 1 | elect 1
--   |      ^
-- ...
singletonStatement :: ExpExtraction.FindCodec -> QuasiQuoter
singletonStatement findCodec = expPreparableStmtAstParser (ExpExtraction.undecodedStatement findCodec Exp.singleRowResultDecoder)

-- |
-- @
-- :: `Statement` params (Maybe row)
-- @
--
-- Statement producing one row or none.
--
-- === __Examples__
--
-- >>> :t [maybeStatement'|select 1 :: int2|]
-- ...
-- ... :: Statement () (Maybe (Maybe Int16))
maybeStatement :: ExpExtraction.FindCodec -> QuasiQuoter
maybeStatement findCodec = expPreparableStmtAstParser (ExpExtraction.undecodedStatement findCodec Exp.rowMaybeResultDecoder)

-- |
-- @
-- :: `Statement` params (`Vector` row)
-- @
--
-- Statement producing a vector of rows.
--
-- === __Examples__
--
-- >>> :t [vectorStatement'|select 1 :: int2|]
-- ...
-- ... :: Statement () (Vector (Maybe Int16))
vectorStatement :: ExpExtraction.FindCodec -> QuasiQuoter
vectorStatement findCodec = expPreparableStmtAstParser (ExpExtraction.undecodedStatement findCodec Exp.rowVectorResultDecoder)

-- |
-- @
-- :: `Fold` row folding -> `Statement` params folding
-- @
--
-- Function from `Fold` over rows to a statement producing the result of folding.
-- Use this when you need to aggregate rows customly.
--
-- === __Examples__
--
-- >>> :t [foldStatement'|SELECT 1 :: int2|]
-- ...
-- ... :: Fold (Maybe Int16) b -> Statement () b
foldStatement :: ExpExtraction.FindCodec ->  QuasiQuoter
foldStatement findCodec = expPreparableStmtAstParser (ExpExtraction.foldStatement findCodec)

-- |
-- @
-- :: `Statement` params ()
-- @
--
-- Statement producing no results.
--
-- === __Examples__
--
-- >>> :t [resultlessStatement'|insert into "user" (name, email) values ($1 :: text, $2 :: text)|]
-- ...
-- ... :: Statement (Maybe Text, Maybe Text) ()
resultlessStatement :: ExpExtraction.FindCodec -> QuasiQuoter
resultlessStatement findCodec = expPreparableStmtAstParser (ExpExtraction.undecodedStatement findCodec (const Exp.noResultResultDecoder))

-- |
-- @
-- :: `Statement` params Int64
-- @
--
-- Statement counting the rows it affects.
--
-- === __Examples__
--
-- >>> :t [rowsAffectedStatement'|delete from "user" where password is null|]
-- ...
-- ... :: Statement () Int64
rowsAffectedStatement :: ExpExtraction.FindCodec -> QuasiQuoter
rowsAffectedStatement findCodec = expPreparableStmtAstParser (ExpExtraction.undecodedStatement findCodec (const Exp.rowsAffectedResultDecoder))

-- * SQL ByteStrings

-- |
-- Quoter of a multiline Unicode SQL string,
-- which gets converted into a format ready to be used for declaration of statements.
uncheckedSql :: QuasiQuoter
uncheckedSql = exp $ pure . Exp.byteString . Text.encodeUtf8 . fromString

-- |
-- Read an SQL-file, containing multiple statements,
-- and produce an expression of type `ByteString`.
--
-- Allows to store plain SQL in external files and read it at compile time.
--
-- E.g.,
--
-- >migration1 :: Hasql.Session.Session ()
-- >migration1 = Hasql.Session.sql [uncheckedSqlFile|migrations/1.sql|]
uncheckedSqlFile :: QuasiQuoter
uncheckedSqlFile = quoteFile uncheckedSql

-- * Tests

-- $
-- >>> :t [maybeStatement'| select (password = $2 :: bytea) :: bool, id :: int4 from "user" where "email" = $1 :: text |]
-- ...
-- ... Statement
-- ...   (Maybe Text, Maybe ByteString) (Maybe (Maybe Bool, Maybe Int32))
--
-- >>> :t [maybeStatement'| select id :: int4 from application where pub_key = $1 :: uuid and sec_key_pt1 = $2 :: int8 and sec_key_pt2 = $3 :: int8 |]
-- ...
-- ... Statement
-- ...   (Maybe UUID, Maybe Int64, Maybe Int64) (Maybe (Maybe Int32))
--
-- >>> :t [singletonStatement'| select 1 :: int4 from a left join b on b.id = a.id |]
-- ...
-- ... Statement () (Maybe Int32)
