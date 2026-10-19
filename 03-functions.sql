-- tsql-proc-testbed: functions. A scalar, an inline table-valued and a multi-statement table-valued,
-- because the three declare their parameters and bodies differently and a reader tuned to one form
-- silently recovers nothing from the others.

-- Scalar. Note the DECIMAL(18,2) in the parameter list: a [^)]*-style argument pattern stops at the
-- inner paren and loses everything after it, which has already bitten the JPA, SQLAlchemy and Django
-- extractors in turn.
CREATE FUNCTION dbo.fn_OrderTotal (@OrderId INT, @Floor DECIMAL(18,2))
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @total DECIMAL(18,2);

    SELECT @total = SUM(l.Amount) FROM dbo.OrderLines l WHERE l.OrderId = @OrderId;

    IF @total IS NULL SET @total = 0;
    IF @total < @Floor SET @total = @Floor;

    RETURN @total;
END
GO

-- Inline table-valued: no BEGIN/END, the body is the RETURN.
CREATE FUNCTION dbo.fn_OpenOrders (@CustomerId INT)
RETURNS TABLE
AS
    RETURN
    (
        SELECT o.OrderId, o.Total
          FROM dbo.Orders o
         WHERE o.CustomerId = @CustomerId
           AND o.Status = 'Open'
    );
GO

-- Multi-statement table-valued: declares its return table, then fills it. The declared return table is
-- not a table in the database and must produce neither a type nor an edge.
CREATE FUNCTION dbo.fn_CustomerSummary (@Region NVARCHAR(50))
RETURNS @summary TABLE (
    CustomerId INT NOT NULL,
    Orders     INT NOT NULL
)
AS
BEGIN
    INSERT INTO @summary (CustomerId, Orders)
    SELECT c.CustomerId, COUNT(o.OrderId)
      FROM dbo.Customers c
      LEFT JOIN dbo.Orders o ON o.CustomerId = c.CustomerId
     WHERE c.Region = @Region
     GROUP BY c.CustomerId;

    RETURN;
END
GO
