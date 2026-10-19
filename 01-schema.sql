-- tsql-proc-testbed: the schema the programmable objects in this fixture operate on.
--
-- Read by SqlSchemaReader (tables and views). Deliberately in the same corpus as the procedures, so
-- the cross-parser contract - a procedure's edge target must be spelled the way the schema parser
-- names its types - can be asserted against what that parser ACTUALLY emits rather than a literal.

CREATE TABLE dbo.Customers (
    CustomerId   INT IDENTITY NOT NULL,
    Name         NVARCHAR(200) NOT NULL,
    Region       NVARCHAR(50) NULL,
    CONSTRAINT PK_Customers PRIMARY KEY (CustomerId)
);
GO

CREATE TABLE dbo.Orders (
    OrderId      INT IDENTITY NOT NULL,
    CustomerId   INT NOT NULL,
    Total        DECIMAL(18,2) NOT NULL,
    PlacedAt     DATETIME2 NOT NULL,
    Status       NVARCHAR(20) NOT NULL,
    CONSTRAINT PK_Orders PRIMARY KEY (OrderId),
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerId) REFERENCES dbo.Customers (CustomerId)
);
GO

CREATE TABLE dbo.OrderLines (
    OrderLineId  INT IDENTITY NOT NULL,
    OrderId      INT NOT NULL,
    Sku          NVARCHAR(40) NOT NULL,
    Quantity     INT NOT NULL,
    Amount       DECIMAL(18,2) NOT NULL,
    CONSTRAINT PK_OrderLines PRIMARY KEY (OrderLineId),
    CONSTRAINT FK_OrderLines_Orders FOREIGN KEY (OrderId) REFERENCES dbo.Orders (OrderId)
);
GO

CREATE TABLE dbo.StagingOrders (
    StagingId    INT IDENTITY NOT NULL,
    CustomerRef  NVARCHAR(40) NOT NULL,
    Total        DECIMAL(18,2) NOT NULL,
    ReceivedAt   DATETIME2 NOT NULL,
    CONSTRAINT PK_StagingOrders PRIMARY KEY (StagingId)
);
GO

CREATE TABLE dbo.StagingCustomers (
    StagingId    INT IDENTITY NOT NULL,
    CustomerRef  NVARCHAR(40) NOT NULL,
    Name         NVARCHAR(200) NOT NULL,
    Region       NVARCHAR(50) NULL,
    CONSTRAINT PK_StagingCustomers PRIMARY KEY (StagingId)
);
GO

CREATE TABLE dbo.AuditLog (
    AuditId      BIGINT IDENTITY NOT NULL,
    Component    NVARCHAR(100) NOT NULL,
    Message      NVARCHAR(1000) NULL,
    LoggedAt     DATETIME2 NOT NULL,
    CONSTRAINT PK_AuditLog PRIMARY KEY (AuditId)
);
GO

CREATE VIEW dbo.vwOpenOrders
AS
    SELECT o.OrderId, o.CustomerId, o.Total
      FROM dbo.Orders o
     WHERE o.Status = 'Open';
GO
