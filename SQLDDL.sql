CREATE DATABASE StoreManagement;
GO

USE StoreManagement;
GO
CREATE TABLE Manager (
    Manager_ID nvarchar(128) PRIMARY KEY,
    Manager_Name NVARCHAR(100) NOT NULL,
    Manager_Phone VARCHAR(15),
    Manager_Email VARCHAR(100)
);
CREATE TABLE Store (
    Store_ID nvarchar(128) PRIMARY KEY,
    Store_Name NVARCHAR(100) NOT NULL,
    Store_Address NVARCHAR(200),
    Manager_ID nvarchar(128),
    Store_Status bit,
    Store_Email NVARCHAR(200) UNIQUE,
    FOREIGN KEY (Manager_ID) REFERENCES Manager(Manager_ID)
);
CREATE TABLE Employee (
    Employee_ID nvarchar(128) PRIMARY KEY,
    Employee_Name NVARCHAR(100) NOT NULL,
    Employee_Gender BIT NOT NULL,
    Employee_Birth DATE,
    Employee_PhoneNumber VARCHAR(15),
    Employee_Email VARCHAR(100),
    Employee_Salary Money,
    Store_Id nvarchar(128),
    FOREIGN KEY (Store_Id) REFERENCES Store(Store_Id),
    CHECK (Employee_Gender IN (0, 1)),

);
CREATE TABLE Customer (
    Customer_ID nvarchar(128) PRIMARY KEY,
    Customer_Name NVARCHAR(100),
    Customer_Phone VARCHAR(15),
    Customer_Email NVARCHAR(128),
    Customer_Gender BIT,
    Store_ID nvarchar(128),
    FOREIGN KEY (Store_Id) REFERENCES Store(Store_ID),
);
CREATE TABLE Product (
    Product_ID nvarchar(128) PRIMARY KEY,
    Product_Name NVARCHAR(100) NOT NULL,
    Product_Provider NVARCHAR(100),
    Product_Price Money NOT NULL
);
CREATE TABLE Inventory (
    Product_ID nvarchar(128),
    Store_ID nvarchar(128),
    Inventory_Stock INT NOT NULL,
    Inventory_Status bit, -- TODO: fix inventory status
    Inventory_AlertQuantity INT,
    FOREIGN KEY (Product_ID) REFERENCES Product(Product_ID),
    FOREIGN KEY (Store_ID) REFERENCES Store(Store_ID),
    PRIMARY KEY (Product_ID, Store_ID),
    CHECK  (Inventory_Stock >= 0),
    CHECK (Inventory_AlertQuantity >= 0),

);
CREATE TABLE Invoice (
    Invoice_ID nvarchar(128) PRIMARY KEY,
    Employee_ID nvarchar(128),
    Customer_ID nvarchar(128),
    Invoice_TotalAmount Money NOT NULL,
    Invoice_Status NVARCHAR(50),
    Invoice_Note NVARCHAR(255),
    Invoice_TotalQuantity INT NOT NULL,
    Invoice_Date DATETIME,
    FOREIGN KEY (Employee_ID) REFERENCES Employee(Employee_ID),
    FOREIGN KEY (Customer_ID) REFERENCES Customer(Customer_ID),
    CHECK (Invoice_TotalAmount >= 0),
    CHECK (Invoice_Status IN ('Paid', 'Not Paid'))

);
CREATE TABLE InvoiceDetail (
    Invoice_ID nvarchar(128),
    Product_ID nvarchar(128),
    InvoiceDetail_Quantity INT,
    InvoiceDetail_UnitPrice Money,
    InvoiceDetail_TotalPrice Money,
    FOREIGN KEY (Invoice_ID) REFERENCES Invoice(Invoice_ID),
    FOREIGN KEY (Product_ID) REFERENCES Product(Product_ID),
    PRIMARY KEY (Invoice_ID, Product_ID),
    CHECK (InvoiceDetail_Quantity > 0)

);

CREATE TABLE Import (
    Import_ID nvarchar(128) PRIMARY KEY,
    Product_ID nvarchar(128),
    Store_ID nvarchar(128),
    Import_Quantity INT,
    Import_Provider NVARCHAR(100),
    Import_Price Money,
    Import_Date DATE,
    Import_Total MONEY,
    FOREIGN KEY (Product_ID) REFERENCES Product(Product_ID),
    FOREIGN KEY (Store_ID) REFERENCES Store(Store_ID),
    CHECK (Import_Quantity > 0)

);

CREATE TABLE Export (
    Export_ID nvarchar(128) PRIMARY KEY,
    Product_ID nvarchar(128),
    Store_ID nvarchar(128),
    Export_Quantity INT,
    Export_Provider NVARCHAR(100),
    Export_Price Money,
    Export_Date DATE
    FOREIGN KEY (Product_ID) REFERENCES Product(Product_ID),
    FOREIGN KEY (Store_ID) REFERENCES Store(Store_ID),
    CHECK (Export_Quantity > 0)
);

CREATE TABLE Shift (
    Employee_ID nvarchar(128),
    Day_of_Week TINYINT,         -- 1=Chủ nhật, 2=Thứ 2, 3=Thứ 3, ..., 7=Thứ 7
    Shift_Start TIME,
    Shift_Finish TIME,
    Is_Active BIT DEFAULT 1,     -- Cho phép tạm dừng lịch làm việc
    PRIMARY KEY (Employee_ID, Day_of_Week),
    FOREIGN KEY (Employee_ID) REFERENCES Employee(Employee_ID),
    CHECK (Day_of_Week BETWEEN 1 AND 7),
    CHECK (Shift_Start < Shift_Finish)
);

CREATE TABLE Notification (
    Notification_ID varchar(128) PRIMARY KEY,
    Notification_Title NVARCHAR(128),
    Notification_Content NVARCHAR(500),
    Notifcation_Time DATETIME,
    Store_ID NVARCHAR(128) REFERENCES Store(Store_ID)
)
GO
    CREATE TABLE Message (
    Id INT IDENTITY(1,1) PRIMARY KEY,         -- Khóa chính tự tăng
    SenderId NVARCHAR(100) NOT NULL,          -- ID người gửi (Store_ID hoặc email manager)
    ReceiverId NVARCHAR(100) NOT NULL,        -- ID người nhận (Store_ID hoặc email manager)
    Content NVARCHAR(MAX) NOT NULL,           -- Nội dung tin nhắn
    Timestamp DATETIME NOT NULL DEFAULT GETDATE()  -- Thời gian gửi tin nhắn
);

-- trigger to prvent user from deleting paid invoices
CREATE TRIGGER prevent_paid_invoice_delete
ON Invoice
INSTEAD OF DELETE
AS
BEGIN
    IF EXISTS (
        SELECT 1 FROM deleted WHERE Invoice_Status = 'Paid'
    )
    BEGIN
        RAISERROR ('Can not delete paid invoice.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    DELETE FROM Invoice
    WHERE Invoice_ID IN (SELECT Invoice_ID FROM deleted);
END;
GO

-- Trigger to automatically update Invoice total amount and quantity
CREATE TRIGGER trg_UpdateInvoiceTotals
ON InvoiceDetail
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Declare variables for affected Invoice IDs
    DECLARE @AffectedInvoices TABLE (Invoice_ID nvarchar(128));
    
    -- Collect all Invoice IDs that need to be updated
    INSERT INTO @AffectedInvoices (Invoice_ID)
    SELECT DISTINCT Invoice_ID FROM inserted
    UNION
    SELECT DISTINCT Invoice_ID FROM deleted;
    
    -- Update Invoice totals for each affected invoice
    UPDATE i
    SET 
        Invoice_TotalAmount = ISNULL(totals.TotalAmount, 0),
        Invoice_TotalQuantity = ISNULL(totals.TotalQuantity, 0)
    FROM Invoice i
    INNER JOIN @AffectedInvoices ai ON i.Invoice_ID = ai.Invoice_ID
    LEFT JOIN (
        SELECT 
            id.Invoice_ID,
            SUM(id.InvoiceDetail_TotalPrice) AS TotalAmount,
            SUM(id.InvoiceDetail_Quantity) AS TotalQuantity
        FROM InvoiceDetail id
        GROUP BY id.Invoice_ID
    ) totals ON i.Invoice_ID = totals.Invoice_ID; 
END;
GO

-- Trigger to automatically update InvoiceDetail UnitPrice and TotalPrice
-- based on the Product's price when InvoiceDetail records are inserted or updated

CREATE TRIGGER trg_UpdateInvoiceDetailPrices
ON InvoiceDetail
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Update UnitPrice and TotalPrice for inserted/updated records
    UPDATE id
    SET 
        InvoiceDetail_UnitPrice = p.Product_Price,
        InvoiceDetail_TotalPrice = id.InvoiceDetail_Quantity * p.Product_Price
    FROM InvoiceDetail id
    INNER JOIN inserted i ON id.Invoice_ID = i.Invoice_ID AND id.Product_ID = i.Product_ID
    INNER JOIN Product p ON id.Product_ID = p.Product_ID;
END;
GO

-- Trigger to automatically update Inventory_Stock when importing products
CREATE TRIGGER trg_UpdateInventoryOnImport
ON Import
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Update existing inventory records
    UPDATE inv
    SET Inventory_Stock = inv.Inventory_Stock + i.Import_Quantity
    FROM Inventory inv
    INNER JOIN inserted i ON inv.Product_ID = i.Product_ID AND inv.Store_ID = i.Store_ID;
    
    -- Insert new inventory records for products that don't exist in the store's inventory
    INSERT INTO Inventory (Product_ID, Store_ID, Inventory_Stock, Inventory_Status, Inventory_AlertQuantity)
    SELECT 
        i.Product_ID,
        i.Store_ID,
        i.Import_Quantity,
        1, -- Default status to active
        10 -- Default alert quality threshold
    FROM inserted i
    WHERE NOT EXISTS (
        SELECT 1 
        FROM Inventory inv 
        WHERE inv.Product_ID = i.Product_ID AND inv.Store_ID = i.Store_ID
    );
    
    PRINT 'Inventory updated successfully after import.';
END;
GO
