-- ระบบจองสนามฟุตบอล KickOff (Term Project 522251) · MySQL 8.0 ขึ้นไป
DROP DATABASE IF EXISTS football_booking;
CREATE DATABASE football_booking CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE football_booking;

CREATE TABLE Customer (
  CustomerID   INT AUTO_INCREMENT PRIMARY KEY,
  FirstName    VARCHAR(50)  NOT NULL,
  LastName     VARCHAR(50)  NOT NULL,
  Phone        VARCHAR(10)  NOT NULL UNIQUE,
  Email        VARCHAR(100) NOT NULL UNIQUE,
  PasswordHash VARCHAR(255) NOT NULL,         -- เก็บค่าแฮชของรหัสผ่าน ไม่เก็บรหัสจริง
  RegisterDate DATE         NOT NULL
);

CREATE TABLE FieldType (
  FieldTypeID  INT AUTO_INCREMENT PRIMARY KEY,
  TypeName     VARCHAR(50)  NOT NULL,
  PlayerSize   INT          NOT NULL,
  PricePerHour DECIMAL(8,2) NOT NULL CHECK (PricePerHour > 0)
);

CREATE TABLE Field (
  FieldID      INT AUTO_INCREMENT PRIMARY KEY,
  FieldTypeID  INT          NOT NULL,
  FieldName    VARCHAR(50)  NOT NULL,
  FieldStatus  ENUM('เปิดให้จอง','ปิดซ่อม') NOT NULL DEFAULT 'เปิดให้จอง',
  FOREIGN KEY (FieldTypeID) REFERENCES FieldType(FieldTypeID)
);

CREATE TABLE Promotion (
  PromotionID     INT AUTO_INCREMENT PRIMARY KEY,
  PromoCode       VARCHAR(20) NOT NULL UNIQUE,
  DiscountPercent INT         NOT NULL CHECK (DiscountPercent BETWEEN 1 AND 100),
  StartDate       DATE        NOT NULL,
  EndDate         DATE        NOT NULL,
  CHECK (EndDate >= StartDate)
);

CREATE TABLE Employee (
  EmployeeID   INT AUTO_INCREMENT PRIMARY KEY,
  FirstName    VARCHAR(50)  NOT NULL,
  LastName     VARCHAR(50)  NOT NULL,
  Phone        VARCHAR(10)  NOT NULL UNIQUE,  -- ใช้เป็นชื่อผู้ใช้เข้าระบบหลังบ้าน
  PasswordHash VARCHAR(255) NOT NULL,
  Position     VARCHAR(50)  NOT NULL
);

CREATE TABLE Booking (
  BookingID     INT AUTO_INCREMENT PRIMARY KEY,
  CustomerID    INT  NOT NULL,
  FieldID       INT  NOT NULL,
  PromotionID   INT  NULL,
  PlayDate      DATE NOT NULL,
  StartTime     TIME NOT NULL,
  EndTime       TIME NOT NULL,
  TotalPrice    DECIMAL(8,2) NOT NULL,
  BookingStatus ENUM('รอชำระเงิน','ยืนยันแล้ว','ยกเลิก') NOT NULL DEFAULT 'รอชำระเงิน',
  CHECK (EndTime > StartTime),
  FOREIGN KEY (CustomerID)  REFERENCES Customer(CustomerID),
  FOREIGN KEY (FieldID)     REFERENCES Field(FieldID),
  FOREIGN KEY (PromotionID) REFERENCES Promotion(PromotionID)
);

CREATE TABLE Equipment (
  EquipmentID   INT AUTO_INCREMENT PRIMARY KEY,
  EquipmentName VARCHAR(50)  NOT NULL,
  RentalPrice   DECIMAL(8,2) NOT NULL,
  StockQty      INT          NOT NULL CHECK (StockQty >= 0)
);

CREATE TABLE Booking_Equipment (
  BookingID   INT NOT NULL,
  EquipmentID INT NOT NULL,
  Quantity    INT NOT NULL CHECK (Quantity > 0),
  PRIMARY KEY (BookingID, EquipmentID),
  FOREIGN KEY (BookingID)   REFERENCES Booking(BookingID),
  FOREIGN KEY (EquipmentID) REFERENCES Equipment(EquipmentID)
);

CREATE TABLE Payment (
  PaymentID     INT AUTO_INCREMENT PRIMARY KEY,
  BookingID     INT NOT NULL UNIQUE,          -- 1 การจอง ชำระ 1 ครั้ง
  EmployeeID    INT NULL,                     -- ว่างได้จนกว่าพนักงานจะตรวจสลิป
  Amount        DECIMAL(8,2) NOT NULL,
  PaymentMethod ENUM('พร้อมเพย์','โอนผ่านธนาคาร','เงินสด') NOT NULL,
  PaymentDate   DATETIME NOT NULL,
  SlipImage     VARCHAR(255) NULL,
  PaymentStatus ENUM('รอตรวจสอบ','ผ่าน','ไม่ผ่าน') NOT NULL DEFAULT 'รอตรวจสอบ',
  FOREIGN KEY (BookingID)  REFERENCES Booking(BookingID),
  FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID)
);

CREATE TABLE Review (
  ReviewID   INT AUTO_INCREMENT PRIMARY KEY,
  BookingID  INT NOT NULL UNIQUE,             -- 1 การจอง รีวิวได้ 1 ครั้ง
  Rating     INT NOT NULL CHECK (Rating BETWEEN 1 AND 5),
  Comment    VARCHAR(500),
  ReviewDate DATE NOT NULL,
  FOREIGN KEY (BookingID) REFERENCES Booking(BookingID)
);

CREATE TABLE Maintenance (
  MaintenanceID INT AUTO_INCREMENT PRIMARY KEY,
  FieldID       INT  NOT NULL,
  EmployeeID    INT  NOT NULL,
  StartDate     DATE NOT NULL,
  EndDate       DATE NOT NULL,
  Detail        VARCHAR(255) NOT NULL,
  CHECK (EndDate >= StartDate),
  FOREIGN KEY (FieldID)    REFERENCES Field(FieldID),
  FOREIGN KEY (EmployeeID) REFERENCES Employee(EmployeeID)
);

-- Trigger: บังคับ Business Rule ที่ CHECK constraint ทำไม่ได้ (ต้องดูข้อมูลจากตารางอื่น)
DELIMITER //

-- กฎข้อ 3, 5, 8: ห้ามจองสนามที่ปิดซ่อม ห้ามจองเวลาทับกัน โค้ดส่วนลดต้องอยู่ในช่วงวันที่ใช้ได้
CREATE TRIGGER trg_booking_check BEFORE INSERT ON Booking
FOR EACH ROW
BEGIN
  IF (SELECT FieldStatus FROM Field WHERE FieldID = NEW.FieldID) = 'ปิดซ่อม'
     OR EXISTS (SELECT 1 FROM Maintenance m
                WHERE m.FieldID = NEW.FieldID AND NEW.PlayDate BETWEEN m.StartDate AND m.EndDate) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'สนามนี้ปิดซ่อมในวันที่เลือก';
  END IF;
  IF EXISTS (SELECT 1 FROM Booking b
             WHERE b.FieldID = NEW.FieldID AND b.PlayDate = NEW.PlayDate AND b.BookingStatus <> 'ยกเลิก'
               AND NEW.StartTime < b.EndTime AND NEW.EndTime > b.StartTime) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ช่วงเวลานี้มีการจองสนามนี้แล้ว';
  END IF;
  IF NEW.PromotionID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Promotion p
             WHERE p.PromotionID = NEW.PromotionID AND NEW.PlayDate BETWEEN p.StartDate AND p.EndDate) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'โค้ดส่วนลดไม่อยู่ในช่วงวันที่ใช้ได้';
  END IF;
END//

-- กฎข้อ 3, 5, 8 ตอนแก้ไขการจอง (เปลี่ยนสนาม/วัน/เวลา/โค้ด หรือดึงการจองที่ยกเลิกกลับมา)
-- ไม่เช็กตอนเปลี่ยนแค่สถานะ เช่น trg_payment_approve เปลี่ยนเป็น "ยืนยันแล้ว"
CREATE TRIGGER trg_booking_update_check BEFORE UPDATE ON Booking
FOR EACH ROW
BEGIN
  IF NEW.BookingStatus <> 'ยกเลิก'
     AND (NEW.FieldID <> OLD.FieldID OR NEW.PlayDate <> OLD.PlayDate
          OR NEW.StartTime <> OLD.StartTime OR NEW.EndTime <> OLD.EndTime
          OR NOT (NEW.PromotionID <=> OLD.PromotionID) OR OLD.BookingStatus = 'ยกเลิก') THEN
    IF (SELECT FieldStatus FROM Field WHERE FieldID = NEW.FieldID) = 'ปิดซ่อม'
       OR EXISTS (SELECT 1 FROM Maintenance m
                  WHERE m.FieldID = NEW.FieldID AND NEW.PlayDate BETWEEN m.StartDate AND m.EndDate) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'สนามนี้ปิดซ่อมในวันที่เลือก';
    END IF;
    IF EXISTS (SELECT 1 FROM Booking b
               WHERE b.BookingID <> NEW.BookingID   -- ไม่นับแถวตัวเอง
                 AND b.FieldID = NEW.FieldID AND b.PlayDate = NEW.PlayDate AND b.BookingStatus <> 'ยกเลิก'
                 AND NEW.StartTime < b.EndTime AND NEW.EndTime > b.StartTime) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ช่วงเวลานี้มีการจองสนามนี้แล้ว';
    END IF;
    IF NEW.PromotionID IS NOT NULL AND NOT EXISTS (SELECT 1 FROM Promotion p
               WHERE p.PromotionID = NEW.PromotionID AND NEW.PlayDate BETWEEN p.StartDate AND p.EndDate) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'โค้ดส่วนลดไม่อยู่ในช่วงวันที่ใช้ได้';
    END IF;
  END IF;
END//

-- กฎข้อ 4: จำนวนที่เช่าต้องไม่เกินจำนวนคงเหลือ ณ ช่วงเวลานั้น
-- คงเหลือ = StockQty - จำนวนที่การจองอื่น (ไม่ยกเลิก) วันเดียวกันและเวลาทับกันเช่าไปแล้ว
CREATE TRIGGER trg_rent_check BEFORE INSERT ON Booking_Equipment
FOR EACH ROW
BEGIN
  IF NEW.Quantity > (SELECT StockQty FROM Equipment WHERE EquipmentID = NEW.EquipmentID)
                    - (SELECT COALESCE(SUM(be.Quantity), 0)
                       FROM Booking_Equipment be
                       JOIN Booking b  ON b.BookingID  = be.BookingID
                       JOIN Booking nb ON nb.BookingID = NEW.BookingID
                       WHERE be.EquipmentID = NEW.EquipmentID
                         AND b.BookingStatus <> 'ยกเลิก'
                         AND b.PlayDate = nb.PlayDate
                         AND b.StartTime < nb.EndTime AND b.EndTime > nb.StartTime) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'จำนวนที่เช่าเกินจำนวนคงเหลือ';
  END IF;
END//

-- กฎข้อ 9: รีวิวได้เฉพาะการจองที่ยืนยันแล้ว และไม่ก่อนวันที่เล่น
CREATE TRIGGER trg_review_check BEFORE INSERT ON Review
FOR EACH ROW
BEGIN
  IF NOT EXISTS (SELECT 1 FROM Booking b
                 WHERE b.BookingID = NEW.BookingID AND b.BookingStatus = 'ยืนยันแล้ว' AND NEW.ReviewDate >= b.PlayDate) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'รีวิวได้เฉพาะการจองที่ยืนยันแล้วและเล่นแล้ว';
  END IF;
END//

-- กฎข้อ 6: พนักงานตรวจสลิปว่าผ่าน การจองเปลี่ยนเป็น "ยืนยันแล้ว" อัตโนมัติ
CREATE TRIGGER trg_payment_approve AFTER UPDATE ON Payment
FOR EACH ROW
BEGIN
  IF NEW.PaymentStatus = 'ผ่าน' AND OLD.PaymentStatus <> 'ผ่าน' THEN
    UPDATE Booking SET BookingStatus = 'ยืนยันแล้ว' WHERE BookingID = NEW.BookingID;
  END IF;
END//

DELIMITER ;

-- ข้อมูลตัวอย่าง (ชื่อสมมติ) ตรงกับหน้าจอใน Prototype · วันปัจจุบันในตัวอย่าง = 1 พ.ย. 2569
INSERT INTO FieldType (TypeName, PlayerSize, PricePerHour) VALUES
 ('สนามหญ้าเทียม 5 คน', 5, 800), ('สนามหญ้าเทียม 7 คน', 7, 1200), ('สนามหญ้าจริง 11 คน', 11, 2500);
INSERT INTO Field (FieldTypeID, FieldName, FieldStatus) VALUES
 (1, 'สนาม A1', 'เปิดให้จอง'), (1, 'สนาม A2', 'เปิดให้จอง'), (2, 'สนาม B1', 'เปิดให้จอง'), (2, 'สนาม B2', 'ปิดซ่อม'), (3, 'สนาม C1', 'เปิดให้จอง');
INSERT INTO Customer (FirstName, LastName, Phone, Email, PasswordHash, RegisterDate) VALUES
 ('สมชาย', 'ใจดี', '0811111111', 'somchai@mail.com', SHA2('somchai1234', 256), '2026-09-01'),
 ('วิภา', 'รักบอล', '0822222222', 'wipa@mail.com', SHA2('wipa1234', 256), '2026-09-15'),
 ('ธนพล', 'ยิงไกล', '0833333333', 'thanapol@mail.com', SHA2('thanapol1234', 256), '2026-10-02');
INSERT INTO Employee (FirstName, LastName, Phone, PasswordHash, Position) VALUES
 ('มานะ', 'ขยัน', '0844444444', SHA2('mana1234', 256), 'แคชเชียร์'),
 ('ปิติ', 'ดูแลดี', '0855555555', SHA2('piti1234', 256), 'ช่างดูแลสนาม'),
 ('ชูใจ', 'บริหาร', '0866666666', SHA2('chujai1234', 256), 'ผู้จัดการ');
INSERT INTO Promotion (PromoCode, DiscountPercent, StartDate, EndDate) VALUES
 ('KICKOFF10', 10, '2026-10-01', '2026-12-31'), ('NOV20', 20, '2026-11-01', '2026-11-30');
INSERT INTO Equipment (EquipmentName, RentalPrice, StockQty) VALUES
 ('ลูกฟุตบอล', 50, 20), ('เสื้อเอี๊ยม (ชุด 10 ตัว)', 100, 10), ('รองเท้าสตั๊ด', 80, 30);
INSERT INTO Maintenance (FieldID, EmployeeID, StartDate, EndDate, Detail) VALUES
 (4, 2, '2026-11-01', '2026-11-10', 'เปลี่ยนหญ้าเทียมบริเวณกรอบเขตโทษ');
-- TotalPrice = (ค่าสนาม + ค่าเช่าอุปกรณ์) x (100 - ส่วนลด%) / 100
INSERT INTO Booking (CustomerID, FieldID, PromotionID, PlayDate, StartTime, EndTime, TotalPrice, BookingStatus) VALUES
 (1, 1, NULL, '2026-10-25', '18:00', '20:00', 1700, 'ยืนยันแล้ว'),  -- 800x2 + บอล 2 ลูก 100
 (2, 3, 1,    '2026-11-06', '19:00', '20:00', 1314, 'รอชำระเงิน'),  -- (1200 + 100 + 160) x 0.9
 (1, 5, NULL, '2026-11-07', '16:00', '18:00', 5000, 'ยกเลิก'),      -- 2500x2
 (3, 1, NULL, '2026-11-05', '18:00', '20:00', 1600, 'ยืนยันแล้ว'),  -- 800x2
 (1, 1, 2,    '2026-11-05', '20:00', '22:00', 1360, 'รอชำระเงิน');  -- (1600 + 100) x 0.8
INSERT INTO Booking_Equipment (BookingID, EquipmentID, Quantity) VALUES (1, 1, 2), (2, 2, 1), (2, 3, 2), (5, 1, 2);
INSERT INTO Payment (BookingID, EmployeeID, Amount, PaymentMethod, PaymentDate, SlipImage, PaymentStatus) VALUES
 (1, 1,    1700, 'พร้อมเพย์',     '2026-10-24 10:15:00', 'slip_0001.jpg', 'ผ่าน'),
 (2, NULL, 1314, 'โอนผ่านธนาคาร', '2026-11-01 12:30:00', 'slip_0002.jpg', 'รอตรวจสอบ'),
 (4, 1,    1600, 'พร้อมเพย์',     '2026-10-30 09:00:00', 'slip_0004.jpg', 'ผ่าน'),
 (5, NULL, 1360, 'พร้อมเพย์',     '2026-11-01 18:40:00', 'slip_0005.jpg', 'รอตรวจสอบ');
INSERT INTO Review (BookingID, Rating, Comment, ReviewDate) VALUES (1, 5, 'หญ้าดี ไฟสว่าง จองง่าย ที่จอดรถกว้าง', '2026-10-25');
