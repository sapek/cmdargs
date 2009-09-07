{-# LANGUAGE PatternGuards #-}

module System.Console.CmdArgs.Flag where

import Data.Dynamic
import Data.List
import Data.Maybe
import Data.Char
import Control.Monad
import Data.Function

import System.Console.CmdArgs.Type


data Action = Update String (Dynamic -> Dynamic)
            | Special String String
            | Error String


---------------------------------------------------------------------
-- HELP INFORMATION FOR A FLAG

helpFlag :: Flag -> [(String,String,String)]
helpFlag xs =
    [(unwords (map ("-"++) short)
     ,unwords (map ("--"++) long) ++ val
     ,flagText xs ++ maybe "" (\x -> " (default=" ++ x ++ ")") (defaultFlag xs))
    | isFlagFlag xs]
    where
        (short,long) = partition ((==) 1 . length) $ flagFlag xs
        val = if isFlagBool xs then ""
              else ['['|opt] ++ "=" ++ flagTypDef "VALUE" xs ++ [']'|opt]
        opt = isFlagOpt xs


-- Given a flag, see what argument positions it should have
-- with the Int being a sort order
helpFlagArgs :: Flag -> [(Int,String)]
helpFlagArgs xs = case (flagArgs xs, flagTypDef "FILE" xs) of
    (Just Nothing,x) -> [(maxBound :: Int,"[" ++ x ++ "]")]
    (Just (Just i),x) -> [(i,x)]
    _ -> []


defaultFlag :: Flag -> Maybe String
defaultFlag x = flagOpt x `mplus` case flagVal x of
    x | Just v <- fromDynamic x, v /= "" -> Just v
      | Just v <- fromDynamic x, v /= (0::Int) -> Just $ show v
      | Just v <- fromDynamic x, v /= (0::Integer) -> Just $ show v
      | Just v <- fromDynamic x, v /= (0::Float) -> Just $ show v
      | Just v <- fromDynamic x, v /= (0::Double) -> Just $ show v
    _ -> Nothing


---------------------------------------------------------------------
-- PROCESS A FLAG

processFlags :: [Flag] -> [String] -> [Action]
processFlags flags = f 0
    where
        f seen [] = case reverse $ sort [i | Flag{flagArgs=Just (Just i),flagOpt=Nothing} <- flags, i < seen] of
            [] -> []
            x:_ -> [Error $ "Not enough non-flag arguments, expected " ++ show x]

        f seen (x:xs) = act : f (seen + if "-" `isPrefixOf` x then 1 else 0) ys
            where (act,ys) = case sortBy (compare `on` fst) $ mapMaybe (\flag -> processFlag flag seen (x:xs)) flags of
                    [] -> (Error $ "Unknown flag: " ++ x, xs)
                    r1:r2:_ | fst r1 == fst r2 -> (Error $ "Ambiguous flag: " ++ x, xs)
                    r:_ -> snd r


data Priority = PriExactFlag | PriPrefixFlag | PriFilePos | PriFile | PriUnknown
                deriving (Eq,Ord,Show)


processFlag :: Flag -> Int -> [String] -> Maybe (Priority, (Action, [String]))

processFlag flag seen (('-':x:xs):ys) | xs /= "" && x `elem` expand = processFlag flag seen (['-',x]:('-':xs):ys)
    where expand = [x | isFlagBool flag, [x] <- flagFlag flag]

processFlag flag seen (('-':x:xs):ys) | x /= '-' = processFlag flag seen (x2:ys)
    where x2 = '-':'-':x:['='| xs /= [] && head xs /= '=']++xs

processFlag flag seen (('-':'-':x):xs)
    | not $ any (a `isPrefixOf`) (flagFlag flag) = Nothing
    | otherwise = Just $ (,) (if a `elem` flagFlag flag then PriExactFlag else PriPrefixFlag) $
    case flagType flag of
        FlagBool r ->
            if b /= "" then err "does not take an argument" xs
                       else upd (const r) xs
        FlagItem r ->
            if not (isFlagOpt flag) && null b && (null xs || "-" `isPrefixOf` head xs)
            then err "needs an argument" xs
            else let (text,rest) = case flagOpt flag of
                        Just v | null b -> (v, xs)
                        _ | null b -> (head xs, tail xs)
                        _ -> (drop 1 b, xs)
                 in case r text of
                        Nothing -> err "couldn't parse argument" rest
                        Just v -> upd v rest
    where
        (a,b) = break (== '=') x
        err msg rest = (Error $ "Error on flag " ++ show x ++ ", flag " ++ msg, rest)
        upd v rest = (Update (flagName flag) v, rest)

processFlag flag seen (x:xs) = case flagArgs flag of
    Just Nothing -> upd PriFile
    Just (Just i) | i == seen -> upd PriFilePos
    _ | flagUnknown flag -> upd PriUnknown
    _ -> Nothing
    where upd p = Just (p, (Update (flagName flag) (\v -> toDyn $ fromDyn v [""] ++ [x]), xs))
