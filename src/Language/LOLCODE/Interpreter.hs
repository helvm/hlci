module Language.LOLCODE.Interpreter where

import           Control.Monad.State     (StateT, get, modify, put, runStateT)
import           Data.List               (nubBy)
import           Data.Maybe              (mapMaybe)
import           Language.LOLCODE.Syntax

type Store = [(String, Expr)]

data Env = Env { globals :: Store
               , locals  :: Store
               } deriving (Eq, Ord, Show)

type Interp a = StateT Env IO a

lookupEnv :: (Env -> Store) -> String -> Interp Expr
lookupEnv f name = do
    env <- get
    case lookup name (f env) of
        Nothing -> fail ("Unbounded variable '" ++ name ++ "'")
        Just ex -> return ex

eval :: Expr -> Interp Expr

eval (Numbr v) = return (Numbr v)

eval (Numbar v) = return (Numbar v)

eval (Noob v) = return (Noob v)

eval (Yarn v) = return (Yarn v)

eval (Troof v) = return (Troof v)

eval (Var name) = lookupEnv locals name

eval p@(Function name args body) = return p

eval (Call name exprs) = do
    func <- lookupEnv globals name
    case func of
        Function _ args prog -> do
            env <- get
            let current = locals env
                locals' = zip args exprs ++ [("IT", Noob "IT")]
            put $ env { locals = locals' }
            exec prog
            ret <- lookupEnv locals "IT"
            put $ env { locals = current }
            return ret
        _ -> fail ("Attempting to call a non-function '" ++ name ++ "'")

eval p@_ = fail $ "Expression not implemented: " ++ show p

exec :: Stmt -> Interp ()

pushLocal :: String -> Expr -> Interp ()
pushLocal name ex = do
    env <- get
    put $ env { locals = (name, ex):(locals env) }

exec (Seq []) = return ()

exec (Seq (s:ss)) = do
    exec s
    case s of
        Return _ -> return ()
        _ -> exec (Seq ss)

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

initEnv :: Stmt -> Env
initEnv prog = Env { globals = initGlobals prog
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