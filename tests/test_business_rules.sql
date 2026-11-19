-- Automated checks for every business rule enforced by CHECK constraints and triggers.
-- Run on a FRESH database right after football_booking.sql:
--   mysql -u root -p < football_booking.sql
--   mysql -u root -p football_booking < tests/test_business_rules.sql
-- Every row of the final result should say PASS.

USE football_booking;
DROP TABLE IF EXISTS _test_result;
CREATE TABLE _test_result (id INT AUTO_INCREMENT PRIMARY KEY, test VARCHAR(120), result VARCHAR(200));

DROP PROCEDURE IF EXISTS expect_error;
DROP PROCEDURE IF EXISTS expect_ok;
DROP PROCEDURE IF EXISTS expect_value;
DELIMITER //
-- Runs a statement that must be rejected.
CREATE PROCEDURE expect_error(IN name VARCHAR(120), IN stmt TEXT)
BEGIN
  DECLARE msg TEXT;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 msg = MESSAGE_TEXT;
    INSERT INTO _test_result (test, result) VALUES (name, CONCAT('PASS (rejected: ', LEFT(msg, 80), ')'));
  END;
  SET @s = stmt;
  PREPARE q FROM @s; EXECUTE q; DEALLOCATE PREPARE q;
  INSERT INTO _test_result (test, result) VALUES (name, 'FAIL: statement was accepted');
END//
-- Runs a statement that must be accepted.
CREATE PROCEDURE expect_ok(IN name VARCHAR(120), IN stmt TEXT)
BEGIN
  DECLARE msg TEXT;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 msg = MESSAGE_TEXT;
    INSERT INTO _test_result (test, result) VALUES (name, CONCAT('FAIL: ', LEFT(msg, 150)));
  END;
  SET @s = stmt;
  PREPARE q FROM @s; EXECUTE q; DEALLOCATE PREPARE q;
  INSERT INTO _test_result (test, result) VALUES (name, 'PASS');
END//
CREATE PROCEDURE expect_value(IN name VARCHAR(120), IN actual TEXT, IN expected TEXT)
BEGIN
  INSERT INTO _test_result (test, result)
  VALUES (name, IF(actual <=> expected, 'PASS', CONCAT('FAIL: got ', COALESCE(actual, 'NULL'), ', expected ', expected)));
END//
DELIMITER ;

-- ---- seed data is consistent ----
CALL expect_value('Seed: 5 bookings loaded', (SELECT COUNT(*) FROM Booking), '5');
CALL expect_value('Seed: TotalPrice of booking 2 = (1200 + 100 + 2x80) x 0.9',
  (SELECT TotalPrice FROM Booking WHERE BookingID = 2), '1314.00');

-- ---- CHECK constraints ----
CALL expect_error('CHECK: end time must be after start time',
  "INSERT INTO Booking (CustomerID, FieldID, PlayDate, StartTime, EndTime, TotalPrice) VALUES (1, 2, '2026-11-20', '20:00', '19:00', 800)");
CALL expect_error('CHECK: rating must be 1-5',
  "INSERT INTO Review (BookingID, Rating, ReviewDate) VALUES (4, 6, '2026-11-05')");
CALL expect_error('CHECK: discount must be 1-100%',
  "INSERT INTO Promotion (PromoCode, DiscountPercent, StartDate, EndDate) VALUES ('BAD', 150, '2026-11-01', '2026-11-30')");
CALL expect_error('CHECK: stock cannot be negative',
  "UPDATE Equipment SET StockQty = -1 WHERE EquipmentID = 1");
CALL expect_error('UNIQUE: one payment per booking',
  "INSERT INTO Payment (BookingID, Amount, PaymentMethod, PaymentDate) VALUES (1, 1700, 'เงินสด', '2026-10-25 10:00:00')");

-- ---- Rule 3: no booking on a field under repair ----
CALL expect_error('Rule 3: field status is closed for repair',
  "INSERT INTO Booking (CustomerID, FieldID, PlayDate, StartTime, EndTime, TotalPrice) VALUES (1, 4, '2026-11-20', '18:00', '19:00', 1200)");
INSERT INTO Maintenance (FieldID, EmployeeID, StartDate, EndDate, Detail) VALUES (3, 2, '2026-11-20', '2026-11-21', 'test');
CALL expect_error('Rule 3: date falls inside a maintenance window',
  "INSERT INTO Booking (CustomerID, FieldID, PlayDate, StartTime, EndTime, TotalPrice) VALUES (1, 3, '2026-11-21', '18:00', '19:00', 1200)");

-- ---- Rule 5: no overlapping bookings on the same field ----
CALL expect_error('Rule 5: overlaps booking 4 (18:00-20:00)',
  "INSERT INTO Booking (CustomerID, FieldID, PlayDate, StartTime, EndTime, TotalPrice) VALUES (2, 1, '2026-11-05', '19:00', '21:00', 1600)");
CALL expect_ok('Rule 5: back-to-back slot (22:00-23:00) is allowed',
  "INSERT INTO Booking (CustomerID, FieldID, PlayDate, StartTime, EndTime, TotalPrice) VALUES (2, 1, '2026-11-05', '22:00', '23:00', 800)");
CALL expect_ok('Rule 5: a cancelled booking frees its slot',
  "INSERT INTO Booking (CustomerID, FieldID, PlayDate, StartTime, EndTime, TotalPrice) VALUES (3, 5, '2026-11-07', '16:00', '18:00', 5000)");
CALL expect_error('Rule 5: re-activating the cancelled booking now clashes',
  "UPDATE Booking SET BookingStatus = 'รอชำระเงิน' WHERE BookingID = 3");
CALL expect_error('Rule 5: moving booking 5 onto booking 4''s slot',
  "UPDATE Booking SET StartTime = '19:00', EndTime = '21:00' WHERE BookingID = 5");
CALL expect_ok('Rule 5: editing a booking does not clash with itself',
  "UPDATE Booking SET EndTime = '21:30' WHERE BookingID = 5");

-- ---- Rule 8: promo code must be valid on the play date ----
CALL expect_error('Rule 8: NOV20 used on 5 Dec',
  "INSERT INTO Booking (CustomerID, FieldID, PromotionID, PlayDate, StartTime, EndTime, TotalPrice) VALUES (1, 2, 2, '2026-12-05', '18:00', '19:00', 640)");
CALL expect_ok('Rule 8: KICKOFF10 used on 5 Dec',
  "INSERT INTO Booking (CustomerID, FieldID, PromotionID, PlayDate, StartTime, EndTime, TotalPrice) VALUES (1, 2, 1, '2026-12-05', '18:00', '19:00', 720)");

-- ---- Rule 4: rented quantity cannot exceed stock left in that time slot ----
-- 10 vest sets in stock; booking 2 (6 Nov 19:00-20:00) already rents 1.
INSERT INTO Booking (CustomerID, FieldID, PlayDate, StartTime, EndTime, TotalPrice) VALUES (3, 2, '2026-11-06', '19:00', '20:00', 800);
SET @b = LAST_INSERT_ID();
CALL expect_error('Rule 4: 10 vest sets when only 9 are free',
  CONCAT('INSERT INTO Booking_Equipment (BookingID, EquipmentID, Quantity) VALUES (', @b, ', 2, 10)'));
CALL expect_ok('Rule 4: 9 vest sets fits',
  CONCAT('INSERT INTO Booking_Equipment (BookingID, EquipmentID, Quantity) VALUES (', @b, ', 2, 9)'));

-- ---- Rule 9: review only a confirmed booking, on or after the play date ----
CALL expect_error('Rule 9: review of an unpaid booking',
  "INSERT INTO Review (BookingID, Rating, ReviewDate) VALUES (2, 4, '2026-11-06')");
CALL expect_error('Rule 9: review before the play date',
  "INSERT INTO Review (BookingID, Rating, ReviewDate) VALUES (4, 4, '2026-11-04')");
CALL expect_ok('Rule 9: review of a confirmed, played booking',
  "INSERT INTO Review (BookingID, Rating, ReviewDate) VALUES (4, 4, '2026-11-05')");

-- ---- Rule 6: approving the slip confirms the booking ----
UPDATE Payment SET PaymentStatus = 'ผ่าน', EmployeeID = 1 WHERE BookingID = 2;
CALL expect_value('Rule 6: booking 2 becomes confirmed after payment approval',
  (SELECT BookingStatus FROM Booking WHERE BookingID = 2), 'ยืนยันแล้ว');

SELECT id, test, result FROM _test_result ORDER BY id;
SELECT CONCAT(SUM(result LIKE 'PASS%'), ' / ', COUNT(*), ' tests passed') AS summary FROM _test_result;
