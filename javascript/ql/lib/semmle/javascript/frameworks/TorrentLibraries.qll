/**
 * Provides classes for modeling Torrent libraries.
 */

import javascript

/**
 * Provides classes for working with [parse-torrent](https://github.com/webtorrent/parse-torrent) code.
 */
module ParseTorrent {
  private API::Node mod() { result = API::moduleImport("parse-torrent") }

  /**
   * A torrent that has been parsed into a JavaScript object.
   */
  class ParsedTorrent extends DataFlow::SourceNode {
    API::Node node;

    ParsedTorrent() {
      (
        node = mod().getReturn() or
        node = mod().getMember("remote").getParameter(1).getParameter(1)
      ) and
      this = node.asSource()
    }

    /** Gets the API node for this torrent object. */
    API::Node asApiNode() { result = node }
  }

  /** Gets a data flow node referring to a parsed torrent. */
  DataFlow::SourceNode parsedTorrentRef() {
    result = any(ParsedTorrent t).asApiNode().getAValueReachableFromSource()
  }

  /**
   * An access to user-controlled torrent information.
   */
  class UserControlledTorrentInfo extends RemoteFlowSource {
    UserControlledTorrentInfo() { none() }

    override string getSourceType() { result = "torrent information" }
  }
}
