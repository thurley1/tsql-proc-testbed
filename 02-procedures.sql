-- tsql-proc-testbed: stored procedures.
--
-- Every procedure here exists to pin one claim. Counts are in README.md and asserted exactly.

-- ---------------------------------------------------------------------------------------------------
-- The branchy one. Reads StagingOrders, writes Orders, calls usp_WriteAudit.
-- Uses a temp table, a table variable and a CTE - none of which is a table, and none of which may
-- produce a type OR an edge. Branchy enough that its complexity must come back non-zero: a body-less
-- type reads as clean code rather than as an error, which is the trap this guards.
-- ---------------------------------------------------------------------------------------------------
CREATE PROCEDURE dbo.usp_LoadOrders
    @ReceivedAfter DATETIME2,
    @BatchSize     INT = 500,
    @Loaded        INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @skipped TABLE (StagingId INT NOT NULL);

    CREATE TABLE #staged (
        StagingId   INT NOT NULL,
        CustomerRef NVARCHAR(40) NOT NULL,
        Total       DECIMAL(18,2) NOT NULL
    );

    BEGIN TRY
        WITH Recent AS (
            SELECT s.StagingId, s.CustomerRef, s.Total
              FROM dbo.StagingOrders s
             WHERE s.ReceivedAt >= @ReceivedAfter
        )
        INSERT INTO #staged (StagingId, CustomerRef, Total)
        SELECT r.StagingId, r.CustomerRef, r.Total FROM Recent r;

        SET @Loaded = 0;

        WHILE EXISTS (SELECT 1 FROM #staged)
        BEGIN
            DECLARE @ref NVARCHAR(40);
            DECLARE @total DECIMAL(18,2);

            SELECT TOP 1 @ref = t.CustomerRef, @total = t.Total FROM #staged t;

            IF @total IS NULL OR @total <= 0
            BEGIN
                INSERT INTO @skipped (StagingId)
                SELECT TOP 1 t.StagingId FROM #staged t;
            END
            ELSE IF @total > 1000000
            BEGIN
                INSERT INTO @skipped (StagingId)
                SELECT TOP 1 t.StagingId FROM #staged t;
            END
            ELSE
            BEGIN
                INSERT INTO dbo.Orders (CustomerId, Total, PlacedAt, Status)
                SELECT c.CustomerId,
                       @total,
                       SYSUTCDATETIME(),
                       CASE WHEN @total > 10000 THEN 'Review' ELSE 'Open' END
                  FROM dbo.Customers c
                 WHERE c.Name = @ref;

                SET @Loaded = @Loaded + 1;
            END

            DELETE FROM #staged WHERE CustomerRef = @ref;

            IF @Loaded >= @BatchSize BREAK;
        END

        EXEC dbo.usp_WriteAudit @Component = 'usp_LoadOrders', @Message = 'batch complete';
    END TRY
    BEGIN CATCH
        EXEC dbo.usp_WriteAudit @Component = 'usp_LoadOrders', @Message = 'batch failed';
        THROW;
    END CATCH

    DROP TABLE #staged;
END
GO

-- ---------------------------------------------------------------------------------------------------
-- Writes one table, reads none. The callee of usp_LoadOrders and trg_Orders_Audit.
-- ---------------------------------------------------------------------------------------------------
CREATE PROCEDURE dbo.usp_WriteAudit
    @Component NVARCHAR(100),
    @Message   NVARCHAR(1000)
AS
BEGIN
    INSERT INTO dbo.AuditLog (Component, Message, LoggedAt)
    VALUES (@Component, @Message, SYSUTCDATETIME());
END
GO

-- ---------------------------------------------------------------------------------------------------
-- MERGE. The target is a write and the USING source is a read - a read sitting inside a write
-- statement, which is one of the three shapes that can silently come out backwards.
-- ---------------------------------------------------------------------------------------------------
CREATE PROCEDURE dbo.usp_MergeCustomers
AS
BEGIN
    MERGE INTO dbo.Customers AS target
    USING dbo.StagingCustomers AS source
       ON target.Name = source.Name
    WHEN MATCHED THEN
        UPDATE SET target.Region = source.Region
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (Name, Region) VALUES (source.Name, source.Region);
END
GO

-- ---------------------------------------------------------------------------------------------------
-- UPDATE ... FROM. The update target is an ALIAS defined in the FROM clause, so a naive reading
-- records a write to a table called "o". Orders is written and also read (the SET reads its own
-- column); OrderLines is read only. Getting OrderLines recorded as a write would put the arrow
-- backwards in every lineage diagram, and the diagram would still look plausible.
-- ---------------------------------------------------------------------------------------------------
CREATE PROCEDURE dbo.usp_AdjustTotals
AS
BEGIN
    UPDATE o
       SET o.Total = o.Total + l.Amount
      FROM dbo.Orders o
      JOIN dbo.OrderLines l ON l.OrderId = o.OrderId
     WHERE o.Status = 'Open';
END
GO

-- ---------------------------------------------------------------------------------------------------
-- DELETE FROM. The FROM here belongs to the DELETE, so AuditLog is a write and NOT a read. Treating
-- every FROM as a read would report a purge procedure as reading the table it empties.
-- ---------------------------------------------------------------------------------------------------
CREATE PROCEDURE dbo.usp_DeleteStaleAudit
    @Before DATETIME2
AS
BEGIN
    DELETE FROM dbo.AuditLog WHERE LoggedAt < @Before;
END
GO

-- ---------------------------------------------------------------------------------------------------
-- OUTPUT ... INTO. Orders is a write; INSERTED is not a table and the table variable is not a table.
-- ---------------------------------------------------------------------------------------------------
CREATE PROCEDURE dbo.usp_InsertOrderWithOutput
    @CustomerId INT,
    @Total      DECIMAL(18,2)
AS
BEGIN
    DECLARE @inserted TABLE (OrderId INT NOT NULL);

    INSERT INTO dbo.Orders (CustomerId, Total, PlacedAt, Status)
    OUTPUT INSERTED.OrderId INTO @inserted (OrderId)
    VALUES (@CustomerId, @Total, SYSUTCDATETIME(), 'Open');

    SELECT i.OrderId FROM @inserted i;
END
GO

-- ---------------------------------------------------------------------------------------------------
-- Dynamic SQL, and NOTHING else. This procedure must emit ZERO data edges: the table name inside the
-- string literal is not evidence of anything, and inferring it would manufacture an edge nobody can
-- check. The negative half is the half that fails silently, so it is asserted too.
-- The EXEC of a variable procedure name is an unresolved call, recorded as such rather than dropped.
-- ---------------------------------------------------------------------------------------------------
CREATE PROCEDURE dbo.usp_BuildDynamicReport
    @TableName SYSNAME,
    @ProcName  SYSNAME
AS
BEGIN
    DECLARE @sql NVARCHAR(MAX);

    SET @sql = N'SELECT * FROM dbo.Orders o JOIN dbo.OrderLines l ON l.OrderId = o.OrderId';
    SET @sql = @sql + N'; INSERT INTO dbo.AuditLog (Component) VALUES (''dynamic'')';

    EXEC sp_executesql @sql;
    EXEC @ProcName;
END
GO

-- ---------------------------------------------------------------------------------------------------
-- A three-part name. Resolving it to the bare "Orders" would silently merge two databases' same-named
-- tables into one node, so it is held apart and lands in the referenced-but-not-defined list instead.
-- ---------------------------------------------------------------------------------------------------
CREATE PROCEDURE dbo.usp_CompareWithArchive
AS
BEGIN
    SELECT a.OrderId
      FROM ArchiveDb.dbo.Orders a
      JOIN dbo.Orders o ON o.OrderId = a.OrderId;
END
GO

-- ---------------------------------------------------------------------------------------------------
-- A body that cannot be read confidently. The BEGIN is never closed. This must flag the object partial
-- and keep what was recovered, never throw.
-- ---------------------------------------------------------------------------------------------------
CREATE PROCEDURE dbo.usp_Unterminated
    @Id INT
AS
BEGIN
    IF @Id > 0
    BEGIN
        SELECT s.StagingId FROM dbo.StagingOrders s WHERE s.StagingId = @Id;
