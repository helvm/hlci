module Language.LOLCODE.Interpreter where

import           Control.Monad.State     (StateT, get, liftIO, liftM, modify,
                                          put, runStateT)
import           Data.List               (find, intercalate, nubBy)
import           Data.Maybe              (mapMaybe)
import           Language.LOLCODE.Syntax

type Store = [(String, Expr)]

data Env = Env { globals      :: Store
               , locals       :: Store
               , return_id    :: Int
               , return_token :: Int
               , break_id     :: Int
               , break_token  :: Int
               , breakable    :: Bool
               } deriving (Eq, Ord, Show)

type Interp a = StateT Env IO a

lookupEnv :: (Env -> Store) -> String -> Interp Expr
lookupEnv f name = do
    env <- get
    case lookup name (f env) of
        Nothing -> fail ("Unbounded variable '" ++ name ++ "'")
        Just ex -> return ex

eval :: Expr -> Interp Expr

eval Noob = return Noob

eval (Numbr v) = return (Numbr v)

eval (Numbar v) = return (Numbar v)

eval (Yarn v) = return (Yarn v)

eval (Troof v) = return (Troof v)

eval (Var name) = lookupEnv locals name

eval (Cast Noob YarnT) = return $ Yarn "Noob"

eval (Cast (Troof v) YarnT) = return $ Yarn s
    where s = case v of
            True -> "WIN"
            _ -> "FAIL"

eval (Cast (Numbr v) YarnT) = return $ Yarn (show v)

eval (Cast (Numbar v) YarnT) = return $ Yarn (show v)

eval (Cast (Yarn v) YarnT) = return $ Yarn v

eval (Cast _ NoobT) = return $ Noob

eval (Cast ex TroofT) = return $ Troof $ case ex of
    Noob -> False
    Numbr 0 -> False
    Numbar 0.0 -> False
    Yarn "" -> False
    Troof b -> b
    _ -> True

eval (Cast ex NumbrT) = case ex of
    Numbr v -> return $ Numbr v
    Numbar v -> return $ Numbr $ truncate (v :: Double)
    Troof True -> return $ Numbr 1
    Troof False -> return $ Numbr 0
    Yarn s -> return $ Numbr $ truncate (read s :: Double)
    p@_ -> fail $ "Cannot cast " ++ show p ++ " to Numbr"

eval (Cast ex NumbarT) = case ex of
    Numbr v -> return $ Numbar ((fromIntegral v) :: Double)
    Numbar v -> return $ Numbar v
    Troof True -> return $ Numbar 1.0
    Troof False -> return $ Numbar 0.0
    Yarn s -> return $ Numbar $ (read s :: Double)
    p@_ -> fail $ "Cannot cast " ++ show p ++ " to Numbar"

eval (Cast p@_ vtype) = do
    ex <- eval p
    eval $ Cast ex vtype

eval p@(Function name args body) = return p

eval (Call name exprs) = do
    func <- lookupEnv globals name
    case func of
        Function _ args prog -> do
            env <- get
            let locals' = zip args exprs ++ [("IT", Noob)]
            put $ env { locals = locals'
                      , return_id = return_id env + 1
                      , return_token = 0
                      }
            exec prog
            ret <- lookupEnv locals "IT"
            env' <- get
            put $ env' { locals = locals env
                       , return_id = return_id env
                       , return_token = 0
                       }
            return ret
        _ -> fail ("Attempting to call a non-function '" ++ name ++ "'")

eval (Smoosh exprs) = do
    exprs' <- mapM eval exprs
    strings <- mapM (\ex -> liftM unYarn $ eval $ Cast ex YarnT) exprs'
    return $ Yarn $ intercalate "" strings
    where unYarn x = case x of
            Yarn s -> s
            _ -> ""

eval (Not ex) = do
    Troof v <- eval (Cast ex TroofT)
    return $ Troof $ not v

eval (BinOp Sum x y) = do
    (x', y') <- getNumericPair x y
    return $ op x' y'
        where
            op (Numbr a) (Numbr b) = Numbr (a + b)
            op (Numbar a) (Numbar b) = Numbar (a + b)

eval (BinOp Diff x y) = do
    (x', y') <- getNumericPair x y
    return $ op x' y'
        where
            op (Numbr a) (Numbr b) = Numbr (a - b)
            op (Numbar a) (Numbar b) = Numbar (a - b)

eval (BinOp Produkt x y) = do
    (x', y') <- getNumericPair x y
    return $ op x' y'
        where
            op (Numbr a) (Numbr b) = Numbr (a * b)
            op (Numbar a) (Numbar b) = Numbar (a * b)

eval (BinOp Quoshunt x y) = do
    (x', y') <- getNumericPair x y
    return $ op x' y'
        where
            op (Numbr a) (Numbr b) = Numbr (a `div` b)
            op (Numbar a) (Numbar b) = Numbar (a / b)

eval (BinOp Mod x y) = do
    (x', y') <- getNumericPair x y
    op x' y'
        where
            op (Numbr a) (Numbr b) = return $ Numbr (a `mod` b)
            op (Numbar a) (Numbar b) = fail "MOD not supported for NUMBAR"

eval (BinOp Biggr x y) = do
    (x', y') <- getNumericPair x y
    return $ op x' y'
        where
            op (Numbr a) (Numbr b) = Numbr (max a b)
            op (Numbar a) (Numbar b) = Numbar (max a b)

eval (BinOp Smallr x y) = do
    (x', y') <- getNumericPair x y
    return $ op x' y'
        where
            op (Numbr a) (Numbr b) = Numbr (min a b)
            op (Numbar a) (Numbar b) = Numbar (min a b)

eval (BinOp Both x y) = evalBoolOp (&&) x y

eval (BinOp Either x y) = evalBoolOp (||) x y

eval (BinOp Won x y) = evalBoolOp (\p q -> (p || q) && (not (p && q))) x y

eval (BinOp Saem x y) = do
    x' <- eval x
    y' <- eval y
    return $ op x' y'
        where
            op (Numbr a) (Numbr b) = Troof (a == b)
            op (Numbr a) (Numbar b) = Troof (toDouble a == b)
            op (Numbar a) (Numbr b) = Troof (a == toDouble b)
            op (Numbar a) (Numbar b) = Troof (a == b)
            op p@_ q@_ = Troof (p == q)
            toDouble v = fromIntegral v :: Double

eval (BinOp Diffrint x y) = do
    Troof same <- eval (BinOp Saem x y)
    return $ Troof $ not same

eval (NaryOp All exprs) = evalBoolOpFold and exprs

eval (NaryOp Any exprs) = evalBoolOpFold or exprs

eval p@_ = fail $ "Expression not implemented: " ++ show p

evalNumeric :: Expr -> Interp Expr
evalNumeric ex = do
    ex' <- eval ex
    case ex' of
        p@(Numbr _) -> return p
        p@(Numbar _) -> return p
        p@(Troof _) -> eval (Cast p TroofT)
        p@(Yarn s) -> if '.' `elem` s
            then eval (Cast p NumbarT)
            else eval (Cast p NumbrT)

getNumericPair :: Expr -> Expr -> Interp (Expr, Expr)
getNumericPair x y = do
    x' <- evalNumeric x
    y' <- evalNumeric y
    f x' y'
        where
            f p@(Numbr _) q@(Numbar _) = eval (Cast p NumbarT) >>= (\p' -> return (p', q))
            f p@(Numbar _) q@(Numbr _) = eval (Cast q NumbarT) >>= (\q' -> return (p, q'))
            f p@_ q@_ = return (p, q)

evalBoolOp :: (Bool -> Bool -> Bool) -> Expr -> Expr -> Interp Expr
evalBoolOp f x y = do
    Troof x' <- eval (Cast x TroofT)
    Troof y' <- eval (Cast y TroofT)
    return $ Troof $ f x' y'

evalBoolOpFold :: ([Bool] -> Bool) -> [Expr] -> Interp Expr
evalBoolOpFold f exprs = do
    bools <- mapM (\x -> liftM unTroof $ eval (Cast x TroofT)) exprs
    return $ Troof $ f bools
        where
            unTroof x = case x of
                Troof True -> True
                _ -> False

exec :: Stmt -> Interp ()

pushLocal :: String -> Expr -> Interp ()
pushLocal name ex = do
    env <- get
    put $ env { locals = (name, ex):(locals env) }

exec (Seq []) = return ()

exec (Seq (s:ss)) = do
    exec s
    env <- get
    if (return_token env) == (return_id env) then
        return ()
    else
        if (break_token env) == (break_id env) then
            return ()
        else
            exec (Seq ss)

exec (Assign name ex) = do
    ex' <- eval ex
    pushLocal name ex'

exec (Declare name ex) = do
    ex' <- eval ex
    pushLocal name ex'

exec (ExprStmt ex) = do
    ex' <- eval ex
    pushLocal "IT" ex'

exec (Return ex) = do
    ex' <- eval ex
    pushLocal "IT" ex'
    env <- get
    put $ env { return_token = return_id env }

exec Break = do
    env <- get
    if breakable env then do
        put $ env { break_token = break_id env }
    else do
        pushLocal "IT" Noob
        env <- get
        put $ env { return_token = return_id env }

exec (Print exprs newline) = do
    Yarn s <- eval $ Smoosh exprs
    liftIO $ putStr $ s
    case newline of
        True -> liftIO $ putStr "\n"
        _ -> return ()

exec (Cast2 name tp) = do
    ex <- lookupEnv locals name >>= \x -> eval $ Cast x tp
    pushLocal name ex

exec (If yes pairs no) = do
    ex <- lookupEnv locals "IT"
    let exprs = ex : map fst pairs
        stmts = yes : map snd pairs
    conds <- mapM (\p -> eval p >>= (\x -> eval (Cast x TroofT))) exprs
    let pair = find (unTroof . fst) $ zip conds stmts
            where
                unTroof x = case x of
                    Troof True -> True
                    _ -> False
    case pair of
        Just (_, s) -> exec s
        Nothing -> case no of
            Just p -> exec p
            Nothing -> return ()

exec (Case pairs defc) = do
    let exprs = map fst pairs
        progs = map snd pairs
        parts = map (\i -> Seq $ drop i progs) [0..(length progs - 1)]
    ref <- lookupEnv locals "IT"
    conds <- mapM (\x -> eval (BinOp Saem x ref)) exprs
    let pair = find (unTroof . fst) $ zip conds parts
            where
                unTroof x = case x of
                    Troof True -> True
                    _ -> False
    case pair of
        Just (_, s) -> do
            env <- get
            put $ env { break_id = (break_id env) + 1
                      , break_token = 0
                      , breakable = True }
            exec s
            env' <- get
            put env' { locals = (locals env') ++ (locals env)
                     , break_id = break_id env
                     , break_token = 0
                     , breakable = breakable env }
        Nothing -> case defc of
            Just p -> do
                env <- get
                put $ env { break_id = (break_id env) + 1
                          , break_token = 0
                          , breakable = True }
                exec p
                env' <- get
                put env' { locals = (locals env') ++ (locals env)
                         , break_id = break_id env
                         , break_token = 0
                         , breakable = breakable env }
            Nothing -> return ()

exec p@_ = fail $ "Statement not implemented: " ++ show p

globalFunctions :: Stmt -> Store
globalFunctions prog = case prog of
    Seq statements -> mapMaybe justFunction statements
        where
            justFunction s = case s of
                ExprStmt ex -> case ex of
                    Function name args code -> Just (name, Function name args code)
                    _ -> Nothing
                _ -> Nothing
    ExprStmt ex -> globalFunctions $ Seq [ExprStmt ex]
    _ -> []

initGlobals :: Stmt -> Store
initGlobals prog = globalFunctions prog

emptyEnv :: Env
emptyEnv = Env { globals = []
               , locals = []
               , return_id = 1
               , return_token = 0
               , break_id = 1
               , break_token = 0
               , breakable = False
               }

initEnv :: Stmt -> Env
initEnv prog = emptyEnv { globals = initGlobals prog
                        , locals = []
                        }

cleanup :: Store -> Store
cleanup store = nubBy (\a b -> fst a == fst b) store

runOnEnv :: Stmt -> Env -> IO (Env)
runOnEnv prog env = do
    (_, env') <- runStateT (exec prog) env
    let out = env' { globals = cleanup $ globals env'
                   , locals = cleanup $ locals env'
                   }
    return out

run :: Stmt -> IO (Env)
run prog = runOnEnv prog (initEnv prog)
