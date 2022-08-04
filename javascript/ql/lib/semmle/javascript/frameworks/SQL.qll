/**
 * Provides classes for working with SQL connectors.
 */

import javascript

module SQL {
  /** A string-valued expression that is interpreted as a SQL command. */
  abstract class SqlString extends Expr { }

  private class SqlStringFromModel extends SqlString {
    SqlStringFromModel() { this = ModelOutput::getASinkNode("sql-injection").asSink().asExpr() }
  }

  /**
   * An expression that sanitizes a string to make it safe to embed into
   * a SQL command.
   */
  abstract class SqlSanitizer extends Expr {
    Expr input;
    Expr output;

    /** Gets the input expression being sanitized. */
    Expr getInput() { result = input }

    /** Gets the output expression containing the sanitized value. */
    Expr getOutput() { result = output }
  }
}

/**
 * Provides classes modeling the (API compatible) `mysql` and `mysql2` packages.
 */
private module MySql {
  private DataFlow::SourceNode mysql() { result = DataFlow::moduleImport(["mysql", "mysql2"]) }

  private DataFlow::CallNode createPool() { result = mysql().getAMemberCall("createPool") }

  /** Gets a reference to a MySQL pool. */
  private DataFlow::SourceNode pool(DataFlow::TypeTracker t) {
    t.start() and
    result = createPool()
    or
    exists(DataFlow::TypeTracker t2 | result = pool(t2).track(t2, t))
  }

  /** Gets a reference to a MySQL pool. */
  private DataFlow::SourceNode pool() { result = pool(DataFlow::TypeTracker::end()) }

  /** Gets a call to `mysql.createConnection`. */
  DataFlow::CallNode createConnection() { result = mysql().getAMemberCall("createConnection") }

  /** Gets a reference to a MySQL connection instance. */
  private DataFlow::SourceNode connection(DataFlow::TypeTracker t) {
    t.start() and
    (
      result = createConnection()
      or
      result = pool().getAMethodCall("getConnection").getABoundCallbackParameter(0, 1)
    )
    or
    exists(DataFlow::TypeTracker t2 | result = connection(t2).track(t2, t))
  }

  /** Gets a reference to a MySQL connection instance. */
  DataFlow::SourceNode connection() { result = connection(DataFlow::TypeTracker::end()) }

  /** A call to the MySql `query` method. */
  private class QueryCall extends DatabaseAccess, DataFlow::MethodCallNode {
    QueryCall() { this = [pool(), connection()].getAMethodCall("query") }

    override DataFlow::Node getAResult() { result = this.getCallback(_).getParameter(1) }

    override DataFlow::Node getAQueryArgument() {
      result = this.getArgument(0) or result = this.getOptionArgument(0, "sql")
    }
  }

  /** An expression that is passed to the `query` method and hence interpreted as SQL. */
  class QueryString extends SQL::SqlString {
    QueryString() { this = any(QueryCall qc).getAQueryArgument().asExpr() }
  }

  /** A call to the `escape` or `escapeId` method that performs SQL sanitization. */
  class EscapingSanitizer extends SQL::SqlSanitizer, MethodCallExpr {
    EscapingSanitizer() {
      this = [mysql(), pool(), connection()].getAMethodCall(["escape", "escapeId"]).asExpr() and
      input = this.getArgument(0) and
      output = this
    }
  }

  /** An expression that is passed as user name or password to `mysql.createConnection`. */
  class Credentials extends CredentialsExpr {
    string kind;

    Credentials() {
      exists(string prop |
        this = [createConnection(), createPool()].getOptionArgument(0, prop).asExpr() and
        (
          prop = "user" and kind = "user name"
          or
          prop = "password" and kind = prop
        )
      )
    }

    override string getCredentialsKind() { result = kind }
  }
}

/**
 * Provides classes modeling the PostgreSQL packages, such as `pg` and `pg-promise`.
 */
private module Postgres {
  /** Gets an expression that constructs a new connection pool. */
  DataFlow::InvokeNode newPool() {
    // new require('pg').Pool()
    result = DataFlow::moduleImport("pg").getAConstructorInvocation("Pool")
    or
    // new require('pg-pool')
    result = DataFlow::moduleImport("pg-pool").getAnInstantiation()
  }

  /** Gets a creation of a Postgres client. */
  DataFlow::InvokeNode newClient() {
    result = DataFlow::moduleImport("pg").getAConstructorInvocation("Client")
  }

  /** A call to the Postgres `query` method. */
  private class QueryCall extends DatabaseAccess, DataFlow::MethodCallNode {
    QueryCall() { this = [newClient(), newPool()].getAMethodCall("query") }

    override DataFlow::Node getAResult() {
      this.getNumArgument() = 2 and
      result = this.getCallback(1).getParameter(1)
      or
      this.getNumArgument() = 1 and
      result = this.getAMethodCall("then").getCallback(0).getParameter(0)
      or
      PromiseFlow::loadStep(this.getALocalUse(), result, Promises::valueProp())
    }

    override DataFlow::Node getAQueryArgument() { result = this.getArgument(0) }
  }

  /** An expression that is passed to the `query` method and hence interpreted as SQL. */
  class QueryString extends SQL::SqlString {
    QueryString() {
      this = any(QueryCall qc).getAQueryArgument().asExpr()
      or
      this = API::moduleImport("pg-cursor").getParameter(0).asSink().asExpr()
    }
  }

  /** An expression that is passed as user name or password when creating a client or a pool. */
  class Credentials extends CredentialsExpr {
    string kind;

    Credentials() {
      exists(string prop | this = [newClient(), newPool()].getOptionArgument(0, prop).asExpr() |
        prop = "user" and kind = "user name"
        or
        prop = "password" and kind = prop
      )
    }

    override string getCredentialsKind() { result = kind }
  }

  /** Gets a node referring to the `pg-promise` library (which is not itself a Promise). */
  API::Node pgPromise() { result = API::moduleImport("pg-promise") }

  /** Gets an initialized `pg-promise` library. */
  API::Node pgpMain() {
    result = pgPromise().getReturn()
    or
    result = API::Node::ofType("pg-promise", "IMain")
  }

  /** Gets a database from `pg-promise`. */
  API::Node pgpDatabase() {
    result = pgpMain().getReturn()
    or
    result = API::Node::ofType("pg-promise", "IDatabase")
  }

  /** Gets a connection created from a `pg-promise` database. */
  API::Node pgpConnection() {
    result = pgpDatabase().getMember("connect").getReturn().getPromised()
    or
    result = API::Node::ofType("pg-promise", "IConnected")
  }

  /** Gets a `pg-promise` task object. */
  API::Node pgpTask() {
    exists(API::Node taskMethod |
      taskMethod = pgpObject().getMember(["task", "taskIf", "tx", "txIf"])
    |
      result = taskMethod.getParameter([0, 1]).getParameter(0)
      or
      result = taskMethod.getParameter(0).getMember("cnd").getParameter(0)
    )
    or
    result = API::Node::ofType("pg-promise", "ITask")
  }

  /** Gets a `pg-promise` object which supports querying (database, connection, or task). */
  API::Node pgpObject() {
    result = [pgpDatabase(), pgpConnection(), pgpTask()]
    or
    result = API::Node::ofType("pg-promise", "IBaseProtocol")
  }

  private string pgpQueryMethodName() {
    result =
      [
        "any", "each", "many", "manyOrNone", "map", "multi", "multiResult", "none", "one",
        "oneOrNone", "query", "result"
      ]
  }

  /** A call that executes a SQL query via `pg-promise`. */
  private class PgPromiseQueryCall extends DatabaseAccess, DataFlow::MethodCallNode {
    PgPromiseQueryCall() { this = pgpObject().getMember(pgpQueryMethodName()).getACall() }

    /** Gets an argument interpreted as a SQL string, not including raw interpolation variables. */
    private DataFlow::Node getADirectQueryArgument() {
      result = this.getArgument(0)
      or
      result = this.getOptionArgument(0, "text")
    }

    /**
     * Gets an interpolation parameter whose value is interpreted literally, or is not escaped appropriately for its context.
     *
     * For example, the following are raw placeholders: $1:raw, $1^, ${prop}:raw, $(prop)^
     */
    private string getARawParameterName() {
      exists(string sqlString, string placeholderRegexp, string regexp |
        placeholderRegexp = "\\$(\\d+|[{(\\[/]\\w+[})\\]/])" and // For example: $1 or ${prop}
        sqlString = this.getADirectQueryArgument().getStringValue()
      |
        // Match $1:raw or ${prop}:raw
        regexp = placeholderRegexp + "(:raw|\\^)" and
        result =
          sqlString
              .regexpFind(regexp, _, _)
              .regexpCapture(regexp, 1)
              .regexpReplaceAll("[^\\w\\d]", "")
        or
        // Match $1:value or ${prop}:value unless enclosed by single quotes (:value prevents breaking out of single quotes)
        regexp = placeholderRegexp + "(:value|\\#)" and
        result =
          sqlString
              .regexpReplaceAll("'[^']*'", "''")
              .regexpFind(regexp, _, _)
              .regexpCapture(regexp, 1)
              .regexpReplaceAll("[^\\w\\d]", "")
      )
    }

    /** Gets the argument holding the values to plug into placeholders. */
    private DataFlow::Node getValues() {
      result = this.getArgument(1)
      or
      result = this.getOptionArgument(0, "values")
    }

    /** Gets a value that is plugged into a raw placeholder variable, making it a sink for SQL injection. */
    private DataFlow::Node getARawValue() {
      result = this.getValues() and this.getARawParameterName() = "1" // Special case: if the argument is not an array or object, it's just plugged into $1
      or
      exists(DataFlow::SourceNode values | values = this.getValues().getALocalSource() |
        result = values.getAPropertyWrite(this.getARawParameterName()).getRhs()
        or
        // Array literals do not have PropWrites with property names so handle them separately,
        // and also translate to 0-based indexing.
        result =
          values.(DataFlow::ArrayCreationNode).getElement(this.getARawParameterName().toInt() - 1)
      )
    }

    override DataFlow::Node getAResult() {
      PromiseFlow::loadStep(this.getALocalUse(), result, Promises::valueProp())
    }

    override DataFlow::Node getAQueryArgument() {
      result = this.getADirectQueryArgument()
      or
      result = this.getARawValue()
    }
  }

  /** An expression that is interpreted as SQL by `pg-promise`. */
  class PgPromiseQueryString extends SQL::SqlString {
    PgPromiseQueryString() { this = any(PgPromiseQueryCall qc).getAQueryArgument().asExpr() }
  }
}

/**
 * Provides classes modeling the `sqlite3` package.
 */
private module Sqlite {
  /** Gets a reference to the `sqlite3` module. */
  DataFlow::SourceNode sqlite() {
    result = DataFlow::moduleImport("sqlite3")
    or
    result = sqlite().getAMemberCall("verbose")
  }

  /** Gets an expression that constructs a Sqlite database instance. */
  DataFlow::SourceNode newDb() {
    // new require('sqlite3').Database()
    result = sqlite().getAConstructorInvocation("Database")
  }

  /** Gets a data flow node referring to a Sqlite database instance. */
  private DataFlow::SourceNode db(DataFlow::TypeTracker t) {
    t.start() and
    result = newDb()
    or
    exists(DataFlow::TypeTracker t2 | result = db(t2).track(t2, t))
  }

  /** Gets a data flow node referring to a Sqlite database instance. */
  DataFlow::SourceNode db() { result = db(DataFlow::TypeTracker::end()) }

  /** A call to a Sqlite query method. */
  private class QueryCall extends DatabaseAccess, DataFlow::MethodCallNode {
    QueryCall() { this = db().getAMethodCall(["all", "each", "exec", "get", "prepare", "run"]) }

    override DataFlow::Node getAResult() {
      result = this.getCallback(1).getParameter(1) or
      PromiseFlow::loadStep(this.getALocalUse(), result, Promises::valueProp())
    }

    override DataFlow::Node getAQueryArgument() { result = this.getArgument(0) }
  }

  /** An expression that is passed to the `query` method and hence interpreted as SQL. */
  class QueryString extends SQL::SqlString {
    QueryString() { this = any(QueryCall qc).getAQueryArgument().asExpr() }
  }
}

/**
 * Provides classes modeling the `mssql` package.
 */
private module MsSql {
  /** Gets a reference to the `mssql` module. */
  DataFlow::SourceNode mssql() { result = DataFlow::moduleImport("mssql") }

  /** Gets a data flow node referring to a request object. */
  private DataFlow::SourceNode request(DataFlow::TypeTracker t) {
    t.start() and
    (
      // new require('mssql').Request()
      result = mssql().getAConstructorInvocation("Request")
      or
      // request.input(...)
      result = request().getAMethodCall("input")
    )
    or
    exists(DataFlow::TypeTracker t2 | result = request(t2).track(t2, t))
  }

  /** Gets a data flow node referring to a request object. */
  DataFlow::SourceNode request() { result = request(DataFlow::TypeTracker::end()) }

  /** A tagged template evaluated as a query. */
  private class QueryTemplateExpr extends DatabaseAccess, DataFlow::ValueNode, DataFlow::SourceNode {
    override TaggedTemplateExpr astNode;

    QueryTemplateExpr() { mssql().getAPropertyRead("query").flowsToExpr(astNode.getTag()) }

    override DataFlow::Node getAResult() {
      PromiseFlow::loadStep(this.getALocalUse(), result, Promises::valueProp())
    }

    override DataFlow::Node getAQueryArgument() {
      result = DataFlow::valueNode(astNode.getTemplate().getAnElement())
    }
  }

  /** A call to a MsSql query method. */
  private class QueryCall extends DatabaseAccess, DataFlow::MethodCallNode {
    QueryCall() { this = request().getAMethodCall(["query", "batch"]) }

    override DataFlow::Node getAResult() {
      result = this.getCallback(1).getParameter(1)
      or
      PromiseFlow::loadStep(this.getALocalUse(), result, Promises::valueProp())
    }

    override DataFlow::Node getAQueryArgument() { result = this.getArgument(0) }
  }

  /** An expression that is passed to a method that interprets it as SQL. */
  class QueryString extends SQL::SqlString {
    QueryString() {
      exists(DatabaseAccess dba | dba instanceof QueryTemplateExpr or dba instanceof QueryCall |
        this = dba.getAQueryArgument().asExpr()
      )
    }
  }

  /** An element of a query template, which is automatically sanitized. */
  class QueryTemplateSanitizer extends SQL::SqlSanitizer {
    QueryTemplateSanitizer() {
      this = any(QueryTemplateExpr qte).getAQueryArgument().asExpr() and
      input = this and
      output = this
    }
  }

  /** An expression that is passed as user name or password when creating a client or a pool. */
  class Credentials extends CredentialsExpr {
    string kind;

    Credentials() {
      exists(DataFlow::InvokeNode call, string prop |
        (
          call = mssql().getAMemberCall("connect")
          or
          call = mssql().getAConstructorInvocation("ConnectionPool")
        ) and
        this = call.getOptionArgument(0, prop).asExpr() and
        (
          prop = "user" and kind = "user name"
          or
          prop = "password" and kind = prop
        )
      )
    }

    override string getCredentialsKind() { result = kind }
  }
}

/**
 * Provides classes modeling the `sequelize` package.
 */
private module Sequelize {
  /** Gets a node referring to an instance of the `Sequelize` class. */
  private DataFlow::SourceNode sequelize(DataFlow::TypeTracker t) {
    t.start() and
    result = DataFlow::moduleImport("sequelize").getAnInstantiation()
    or
    exists(DataFlow::TypeTracker t2 | result = sequelize(t2).track(t2, t))
  }

  /** Gets a node referring to an instance of the `Sequelize` class. */
  DataFlow::SourceNode sequelize() { result = sequelize(DataFlow::TypeTracker::end()) }

  /** A call to `Sequelize.query`. */
  private class QueryCall extends DatabaseAccess, DataFlow::ValueNode {
    override MethodCallExpr astNode;

    QueryCall() { this = sequelize().getAMethodCall("query") }

    override DataFlow::Node getAQueryArgument() {
      result = DataFlow::valueNode(astNode.getArgument(0))
    }
  }

  /** An expression that is passed to `Sequelize.query` method and hence interpreted as SQL. */
  class QueryString extends SQL::SqlString {
    QueryString() { this = any(QueryCall qc).getAQueryArgument().asExpr() }
  }

  /**
   * An expression that is passed as user name or password when creating an instance of the
   * `Sequelize` class.
   */
  class Credentials extends CredentialsExpr {
    string kind;

    Credentials() {
      exists(NewExpr ne, string prop |
        ne = sequelize().asExpr() and
        (
          this = ne.getArgument(1) and prop = "username"
          or
          this = ne.getArgument(2) and prop = "password"
          or
          ne.hasOptionArgument(ne.getNumArgument() - 1, prop, this)
        ) and
        (
          prop = "username" and kind = "user name"
          or
          prop = "password" and kind = prop
        )
      )
    }
  }
}

/**
 * Provides classes modelling the Google Cloud Spanner library.
 */
private module Spanner {
  /**
   * Gets a node that refers to the `Spanner` class
   */
  DataFlow::SourceNode spanner() {
    // older versions
    result = DataFlow::moduleImport("@google-cloud/spanner")
    or
    // newer versions
    result = DataFlow::moduleMember("@google-cloud/spanner", "Spanner")
  }

  /** Gets a data flow node referring to the result of `Spanner()` or `new Spanner()`. */
  private DataFlow::SourceNode spannerNew(DataFlow::TypeTracker t) {
    t.start() and
    result = spanner().getAnInvocation()
    or
    exists(DataFlow::TypeTracker t2 | result = spannerNew(t2).track(t2, t))
  }

  /** Gets a data flow node referring to the result of `Spanner()` or `new Spanner()`. */
  DataFlow::SourceNode spannerNew() { result = spannerNew(DataFlow::TypeTracker::end()) }

  /** Gets a data flow node referring to the result of `.instance()`. */
  private DataFlow::SourceNode instance(DataFlow::TypeTracker t) {
    t.start() and
    result = spannerNew().getAMethodCall("instance")
    or
    exists(DataFlow::TypeTracker t2 | result = instance(t2).track(t2, t))
  }

  /** Gets a data flow node referring to the result of `.instance()`. */
  DataFlow::SourceNode instance() { result = instance(DataFlow::TypeTracker::end()) }

  /** Gets a node that refers to an instance of the `Database` class. */
  private DataFlow::SourceNode database(DataFlow::TypeTracker t) {
    t.start() and
    result = instance().getAMethodCall("database")
    or
    exists(DataFlow::TypeTracker t2 | result = database(t2).track(t2, t))
  }

  /** Gets a node that refers to an instance of the `Database` class. */
  DataFlow::SourceNode database() { result = database(DataFlow::TypeTracker::end()) }

  /** Gets a node that refers to an instance of the `v1.SpannerClient` class. */
  private DataFlow::SourceNode v1SpannerClient(DataFlow::TypeTracker t) {
    t.start() and
    result = spanner().getAPropertyRead("v1").getAPropertyRead("SpannerClient").getAnInstantiation()
    or
    exists(DataFlow::TypeTracker t2 | result = v1SpannerClient(t2).track(t2, t))
  }

  /** Gets a node that refers to an instance of the `v1.SpannerClient` class. */
  DataFlow::SourceNode v1SpannerClient() { result = v1SpannerClient(DataFlow::TypeTracker::end()) }

  /** Gets a node that refers to a transaction object. */
  private DataFlow::SourceNode transaction(DataFlow::TypeTracker t) {
    t.start() and
    result = database().getAMethodCall("runTransaction").getABoundCallbackParameter(0, 1)
    or
    exists(DataFlow::TypeTracker t2 | result = transaction(t2).track(t2, t))
  }

  /** Gets a node that refers to a transaction object. */
  DataFlow::SourceNode transaction() { result = transaction(DataFlow::TypeTracker::end()) }

  /**
   * A call to a Spanner method that executes a SQL query.
   */
  abstract class SqlExecution extends DatabaseAccess, DataFlow::InvokeNode {
    /**
     * Gets the position of the query argument; default is zero, which can be overridden
     * by subclasses.
     */
    int getQueryArgumentPosition() { result = 0 }

    override DataFlow::Node getAQueryArgument() {
      result = getArgument(getQueryArgumentPosition()) or
      result = getOptionArgument(getQueryArgumentPosition(), "sql")
    }
  }

  /**
   * A SQL execution that takes the input directly in the first argument or in the `sql` option.
   */
  class DatabaseRunCall extends SqlExecution {
    DatabaseRunCall() {
      this = database().getAMethodCall(["run", "runPartitionedUpdate", "runStream"])
    }
  }

  /**
   * A SQL execution that takes an array of SQL strings or { sql: string } objects.
   */
  class TransactionRunCall extends SqlExecution {
    TransactionRunCall() { this = transaction().getAMethodCall(["run", "runStream", "runUpdate"]) }
  }

  /**
   * A SQL execution that only takes the input in the `sql` option, and do not accept query strings
   * directly.
   */
  class ExecuteSqlCall extends SqlExecution {
    ExecuteSqlCall() {
      this = v1SpannerClient().getAMethodCall(["executeSql", "executeStreamingSql"])
    }
  }
}
