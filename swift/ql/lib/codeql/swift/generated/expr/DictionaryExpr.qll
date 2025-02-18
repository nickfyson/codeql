// generated by codegen/codegen.py
import codeql.swift.elements.expr.CollectionExpr
import codeql.swift.elements.expr.Expr

class DictionaryExprBase extends @dictionary_expr, CollectionExpr {
  override string toString() { result = "DictionaryExpr" }

  Expr getElement(int index) {
    exists(Expr x |
      dictionary_expr_elements(this, index, x) and
      result = x.resolve()
    )
  }

  Expr getAnElement() { result = getElement(_) }

  int getNumberOfElements() { result = count(getAnElement()) }
}
