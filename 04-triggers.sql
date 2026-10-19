-- tsql-proc-testbed: triggers.
--
-- A trigger's writes are IMPLICIT consequences of somebody else's write, which is what makes them the
-- interesting case for end-to-end lineage: the path from the tool that inserts an order to the audit
-- row it causes is two hops through something nobody mentions.
--
-- INSERTED and DELETED are not tables. They match a FROM pattern exactly like a real one and would
-- invent two tables in every trigger-bearing estate.

CREATE TRIGGER dbo.trg_Orders_Audit
ON dbo.Orders
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.AuditLog (Component, Message, LoggedAt)
    SELECT 'trg_Orders_Audit',
           CONCAT('order ', i.OrderId, ' total ', i.Total),
           SYSUTCDATETIME()
      FROM INSERTED i;

    IF EXISTS (SELECT 1 FROM DELETED)
    BEGIN
        EXEC dbo.usp_WriteAudit @Component = 'trg_Orders_Audit', @Message = 'row replaced';
    END
END
GO

-- A second trigger, on a different table, so "the tables a trigger is attached to" is more than one
-- value and a reader that hard-codes the first cannot pass.
CREATE TRIGGER dbo.trg_OrderLines_Total
ON dbo.OrderLines
AFTER INSERT
AS
BEGIN
    UPDATE o
       SET o.Total = o.Total + i.Amount
      FROM dbo.Orders o
      JOIN INSERTED i ON i.OrderId = o.OrderId;
END
GO
