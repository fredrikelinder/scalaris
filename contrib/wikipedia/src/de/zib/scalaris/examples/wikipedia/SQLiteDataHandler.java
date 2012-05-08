/**
 * 
 */
package de.zib.scalaris.examples.wikipedia;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

import com.almworks.sqlite4java.SQLiteConnection;
import com.almworks.sqlite4java.SQLiteException;
import com.almworks.sqlite4java.SQLiteStatement;

import de.zib.scalaris.examples.wikipedia.bliki.MyNamespace;
import de.zib.scalaris.examples.wikipedia.bliki.MyWikiModel.NormalisedTitle;
import de.zib.scalaris.examples.wikipedia.data.Contributor;
import de.zib.scalaris.examples.wikipedia.data.Page;
import de.zib.scalaris.examples.wikipedia.data.Revision;

/**
 * Retrieves and writes values from/to a SQLite DB.
 * 
 * @author Nico Kruber, kruber@zib.de
 */
public class SQLiteDataHandler {

    /**
     * Opens a connection to a database and sets some default PRAGMAs for better
     * performance in our case.
     * 
     * @param fileName
     *            the name of the DB file
     * @param readOnly
     *            whether to open the DB read-only or not
     * @param cacheSize
     *            cache size to set for the DB connection (default if
     *            <tt>null</tt>)
     * 
     * @return the DB connection
     * 
     * @throws SQLiteException
     *             if the connection fails or a pragma could not be set
     */
    public static SQLiteConnection openDB(String fileName, boolean readOnly, Long cacheSize) throws SQLiteException {
        SQLiteConnection db = new SQLiteConnection(new File(fileName));
        if (readOnly) {
            db.openReadonly();
        } else {
            db.open(true);
        }
        // set cache_size:
        if (cacheSize != null) {
            final SQLiteStatement stmt = db.prepare("PRAGMA page_size;");
            if (stmt.step()) {
                long pageSize = stmt.columnLong(0);
                db.exec("PRAGMA cache_size = " + (cacheSize / pageSize) + ";");
            }
            stmt.dispose();
        }
        db.exec("PRAGMA synchronous = OFF;");
        db.exec("PRAGMA journal_mode = OFF;");
        //        db.exec("PRAGMA locking_mode = EXCLUSIVE;");
        db.exec("PRAGMA case_sensitive_like = true;"); 
        db.exec("PRAGMA encoding = 'UTF-8';"); 
        db.exec("PRAGMA temp_store = MEMORY;"); 
        return db;
    }

    /**
     * Opens a connection to a database and sets some default PRAGMAs for better
     * performance in our case.
     * 
     * @param fileName
     *            the name of the DB file
     * @param readOnly
     *            whether to open the DB read-only or not
     * 
     * @return the DB connection
     * 
     * @throws SQLiteException
     *             if the connection fails or a pragma could not be set
     */
    public static SQLiteConnection openDB(String fileName, boolean readOnly) throws SQLiteException {
        return openDB(fileName, readOnly, null);
    }

    /**
     * Wrapper for several prepared statements of a single SQLite connection.
     * 
     * @author Nico Kruber, kruber@zib.de
     */
    public static class Connection {
        /**
         * The DB connection.
         */
        public final SQLiteConnection db;
        
        /**
         * Allows retrieval of the latest revision of a page.
         */
        public SQLiteStatement stmtGetLatestRev;
        
        /**
         * Creates all prepared statements and stores them in the object's
         * members.
         * 
         * @param connection
         *            the SQLite connection to use
         * 
         * @throws SQLiteException
         *             if a prepared statement fails
         */
        public Connection(SQLiteConnection connection) throws SQLiteException {
            this.db = connection;
            initStmts();
        }
        
        /**
         * Creates all prepared statements and stores them in the object's
         * members.
         * 
         * @param fileName
         *            the name of the DB file
         * 
         * @throws SQLiteException
         *             if a prepared statement fails
         */
        public Connection(String fileName) throws SQLiteException {
            this.db = openDB(fileName, true);
            initStmts();
        }

        protected void initStmts() throws SQLiteException {
            stmtGetLatestRev = this.db.prepare("SELECT * from page "
                    + "INNER JOIN revision ON page_latest == rev_id "
                    + "INNER JOIN text ON rev_text_id == old_id "
                    + "WHERE page_namespace == ? AND page_title == ?;");
        }
    }
    
    /**
     * Retrieves the current, i.e. most up-to-date, version of a page from
     * Scalaris.
     * 
     * @param connection
     *            the connection to Scalaris
     * @param title
     *            the title of the page
     * @param nsObject
     *            the namespace for page title de-normalisation
     * 
     * @return a result object with the page and revision on success
     */
    public static RevisionResult getRevision(Connection connection,
            NormalisedTitle title, MyNamespace nsObject) {
        final long timeAtStart = System.currentTimeMillis();
        Page page = null;
        Revision revision = null;
        List<InvolvedKey> involvedKeys = new ArrayList<InvolvedKey>();
        if (connection == null) {
            return new RevisionResult(false, involvedKeys,
                    "no connection to SQLite DB", true, title, page, revision, false,
                    false, title.toString(), System.currentTimeMillis() - timeAtStart);
        }
        
        final SQLiteStatement stmt = connection.stmtGetLatestRev;
        try {
            stmt.bind(1, title.namespace).bind(2, title.title);
            if (stmt.step()) {
                page = new Page();
                page.setTitle(title.denormalise(nsObject));
                revision = new Revision();
                for (int i = 0; i < stmt.columnCount(); i++) {
                    String columnName = stmt.getColumnName(i);
                    if (columnName.equals("page_id")) {
                        page.setId(stmt.columnInt(i));
                    } else if (columnName.equals("page_restrictions")) {
                        page.setRestrictions(Page.restrictionsFromString(stmt.columnString(i)));
                    } else if (columnName.equals("page_is_redirect")) {
                        page.setRedirect(stmt.columnInt(i) != 0);
                    } else if (columnName.equals("rev_id")) {
                        revision.setId(stmt.columnInt(i));
                    } else if (columnName.equals("rev_comment")) {
                        revision.setComment(stmt.columnString(i));
                    } else if (columnName.equals("rev_user_text")) {
                        Contributor contributor = new Contributor();
                        contributor.setIp(stmt.columnString(i));
                        revision.setContributor(contributor);
                    } else if (columnName.equals("rev_timestamp")) {
                        revision.setTimestamp(stmt.columnString(i));
                    } else if (columnName.equals("rev_minor_edit")) {
                        revision.setMinor(stmt.columnInt(i) != 0);
                    } else if (columnName.equals("old_text")) {
                        revision.setB64pText(stmt.columnString(i));
                    }
                }
                page.setCurRev(revision);
            }
            // there should only be one data item
            if (stmt.step()) {
                return new RevisionResult(false, involvedKeys,
                        "more than one result", false, title, page, revision, false,
                        false, title.toString(), System.currentTimeMillis() - timeAtStart);
            }

            return new RevisionResult(involvedKeys, title, page, revision, title.toString(),
                    System.currentTimeMillis() - timeAtStart);
        } catch (SQLiteException e) {
            return new RevisionResult(false, involvedKeys, "SQLite exception: "
                    + e.getMessage(), false, title, page, revision, false,
                    false, title.toString(), System.currentTimeMillis()
                            - timeAtStart);
        } finally {
            try {
                stmt.reset();
            } catch (SQLiteException e) {
            }
        }
    }

}
