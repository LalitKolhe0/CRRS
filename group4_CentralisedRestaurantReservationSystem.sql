Drop database  if exists CentralisedRestaurantReservationSystem;
Create database CentralisedRestaurantReservationSystem;
use CentralisedRestaurantReservationSystem;
SET SQL_SAFE_UPDATES = 0;






/*Status Completed/Required
tables 15/15   
major queries 10/10  
Stored Procedures 6/5  
Functions 5/5
Triggers 3/3
 */  
 
SHOW tables;
SHOW FUNCTION STATUS where Db='CentralisedRestaurantReservationSystem';
SHOW PROCEDURE STATUS where Db='CentralisedRestaurantReservationSystem';
SHOW TRIGGERS;

CREATE TABLE restaurants (
  restaurant_id INT AUTO_INCREMENT PRIMARY KEY, 
  restaurant_name VARCHAR(100), 
  location VARCHAR(255), 
  zip_code VARCHAR(10),
  phone_number VARCHAR(12),
  email VARCHAR(100),
  tax DECIMAL(3,2)
);

CREATE TABLE RTables (
  table_id INT AUTO_INCREMENT PRIMARY KEY,
  restaurant_id INT NOT NULL,
  table_number INT NOT NULL,
  capacity INT NOT NULL,
  FOREIGN KEY (restaurant_id) REFERENCES restaurants(restaurant_id)  ON DELETE CASCADE
);  

CREATE TABLE Employees (
  employee_id INT AUTO_INCREMENT PRIMARY KEY,
  employee_name VARCHAR(50),
  phone_number VARCHAR(12),
  email VARCHAR(100),
  username VARCHAR(50), 
  password VARCHAR(100),
  role ENUM('chef', 'server', 'manager') NOT NULL
);

CREATE TABLE time_slots (
  slot_id INT AUTO_INCREMENT PRIMARY KEY,
  start_time TIME
);

CREATE TABLE Members (
  member_id INT AUTO_INCREMENT PRIMARY KEY,
  customer_id INT,
  username VARCHAR(50) UNIQUE, 
  password_hash VARCHAR(100), -- Hashed password for secure login
  first_name VARCHAR(50), 
  last_name VARCHAR(50),  
  email VARCHAR(100) UNIQUE,
  phone_number VARCHAR(20) UNIQUE,
  login_method ENUM('Website', 'Walk-in', 'Phone Call') NOT NULL,
  member_status ENUM('Just Member','Active', 'Cancelled'),
  cancellation_penalty float default 0
);

CREATE TABLE Bookings (
  booking_id INT AUTO_INCREMENT PRIMARY KEY, 
  member_id INT,
  restaurant_id INT,
  table_id INT,
  start_time_slot INT,
  booking_duration INT, 
  booking_created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  booking_method ENUM('Website', 'Walk-in', 'Phone Call') NOT NULL,
  FOREIGN KEY (member_id) REFERENCES Members(member_id)  ON DELETE CASCADE,
  FOREIGN KEY (restaurant_id) REFERENCES restaurants(restaurant_id) ON DELETE CASCADE,
  FOREIGN KEY (table_id) REFERENCES RTables(table_id) ON DELETE CASCADE,
  FOREIGN KEY (start_time_slot) REFERENCES time_slots(slot_id)  ON DELETE CASCADE
);

create table TableStatus(
	table_id int,
	booking_id int default NULL,
	slot_id int,
	status ENUM('Occupied','Vacant') DEFAULT 'Vacant',
	foreign key (table_id) references rtables(table_id)  ON DELETE CASCADE,
	foreign key (booking_id) references bookings(booking_id)  ON DELETE CASCADE,
	foreign key (slot_id) references time_slots(slot_id) ON DELETE CASCADE
	);

create table BookingStatus(
booking_id INT,
booking_status ENUM('scheduled', 'ongoing', 'completed', 'cancelled' ) NOT NULL DEFAULT 'scheduled',
out_time time default null, 
employee_id INT default null,
cancelled_on TIMESTAMP default null,
last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
foreign key (booking_id) references Bookings(booking_id)  ON DELETE CASCADE
);

-- MenuItems Table
CREATE TABLE MenuItems (
  MenuItem_id INT AUTO_INCREMENT PRIMARY KEY,
  MenuItem_name VARCHAR(255) UNIQUE,
  serving_description TEXT,
  price DECIMAL(5, 2)
);

-- restaurantMenu Table
CREATE TABLE restaurantMenu (
  restaurant_menu_id INT AUTO_INCREMENT PRIMARY KEY,
  restaurant_id INT,
  MenuItem_id INT,
  availability BOOLEAN,
  FOREIGN KEY (restaurant_id) REFERENCES restaurants(restaurant_id)  ON DELETE CASCADE,
  FOREIGN KEY (MenuItem_id) REFERENCES MenuItems(MenuItem_id) ON DELETE CASCADE
);

-- Orders Table
CREATE TABLE Orders (
  order_id INT AUTO_INCREMENT PRIMARY KEY,
  booking_id INT,
  MenuItem_id INT,
  quantity INT,
  order_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (booking_id) REFERENCES Bookings(booking_id)  ON DELETE CASCADE,
  FOREIGN KEY (MenuItem_id) REFERENCES MenuItems(MenuItem_id)   ON DELETE CASCADE
);

CREATE TABLE Billing (
  billing_id INT AUTO_INCREMENT PRIMARY KEY,
  order_id INT UNIQUE,
  total_amount DECIMAL(10, 2),
  payment_status ENUM('pending', 'paid') NOT NULL DEFAULT 'pending',
  payment_date TIMESTAMP,
  FOREIGN KEY (order_id) REFERENCES Orders(order_id)  ON DELETE CASCADE
);

-- Create Past Bookings Table
CREATE TABLE PastBookings (
    booking_id INT,
    total_price DECIMAL(10, 2),
    total_tax DECIMAL(10, 2),
    total_price_after_tax DECIMAL(10, 2),
    booking_created TIMESTAMP,
    FOREIGN KEY (booking_id) REFERENCES Bookings(booking_id) ON DELETE CASCADE
);


-- Workshifts
CREATE TABLE WorkShifts (
  shift_id INT AUTO_INCREMENT PRIMARY KEY,
  employee_id INT,
  restaurant_id INT,
  start_time_slot INT,
  shift_duration INT,
  FOREIGN KEY (employee_id) REFERENCES Employees(employee_id)  ON DELETE CASCADE,
  FOREIGN KEY (restaurant_id) REFERENCES restaurants(restaurant_id)  ON DELETE CASCADE,
  FOREIGN KEY (start_time_slot) REFERENCES time_slots(slot_id) ON DELETE CASCADE
);

-- Trigger and Procedure Logs 
CREATE TABLE programLogs(
log_id INT AUTO_INCREMENT PRIMARY KEY, 
log_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
Message VARCHAR(150)
);



SHOW tables;

-- Fill time slots 
DELIMITER //
CREATE PROCEDURE PopulateTimeSlots()
BEGIN
    DECLARE start_time TIME DEFAULT '10:00:00';
    DECLARE end_time TIME DEFAULT '23:00:00';
    
    WHILE start_time <= end_time DO
        INSERT INTO time_slots (start_time) VALUES (start_time);
        SET start_time = ADDTIME(start_time, '01:00:00');
    END WHILE;    
END//
DELIMITER ;

call PopulateTimeSlots();
select * from time_slots;

-- Function to find the vacant table when a customer make reservation
DELIMITER //
CREATE FUNCTION FindAvailableTable(restaurant_id INT, slot_id INT, booking_duration INT)
RETURNS INT
DETERMINISTIC  
BEGIN
  DECLARE available_table_id INT DEFAULT NULL;
  SELECT ts.table_id INTO available_table_id   FROM TableStatus ts JOIN Rtables rt ON ts.table_id = rt.table_id 
  WHERE rt.restaurant_id = restaurant_id AND ts.slot_id BETWEEN slot_id AND slot_id + booking_duration - 1 AND ts.status = 'Vacant'
  GROUP BY ts.table_id HAVING COUNT(*) = booking_duration LIMIT  1;

  RETURN available_table_id;
END //
DELIMITER ;

-- Prcedure to make a new booking for a customer. Allows only if there is no booking scheduled or going on currently
DROP PROCEDURE IF EXISTS NewBooking;
DELIMITER //
CREATE PROCEDURE NewBooking(IN member_id INT, IN restaurant_id INT, IN start_time_slot INT, IN booking_duration INT, IN booking_method VARCHAR(50))
BEGIN
  DECLARE existing_booking_id INT;
  DECLARE available_table_id INT;
  
  SELECT bookings.booking_id into existing_booking_id FROM bookings JOIN bookingstatus ON bookings.booking_id = bookingstatus.booking_id WHERE bookings.member_id = member_id AND bookingstatus.booking_status in ('scheduled','ongoing') LIMIT 1;
  IF existing_booking_id > 0 THEN
    SELECT concat('Member already has a scheduled booking. Please handle existing booking (ID:', existing_booking_id, ') before creating a new one.') as Message; 
    INSERT INTO ProgramLogs (Message) values (concat('Member ID: ', member_id,' with existing booking with id ', existing_booking_id, ' tried new booking. FAILED!!'));
  ELSE
	  SET available_table_id = FindAvailableTable(restaurant_id, start_time_slot, booking_duration);
	  IF available_table_id IS NOT NULL THEN
		INSERT INTO bookings (member_id, restaurant_id, table_id, start_time_slot, booking_duration, booking_method)
		VALUES (member_id, restaurant_id, available_table_id, start_time_slot, booking_duration, booking_method);
		select 'Booking Confirmed' as Message; 
        SELECT bookings.booking_id into existing_booking_id FROM bookings JOIN bookingstatus ON bookings.booking_id = bookingstatus.booking_id WHERE bookings.member_id = member_id AND bookingstatus.booking_status='scheduled' LIMIT 1;
        INSERT INTO ProgramLogs (Message) values (concat('Booking with ID ',existing_booking_id,' created for member ID',member_id,'. SUCCESS!!' ));
	  ELSE
		SELECT 'No available table found for the requested time slot.';
        INSERT INTO ProgramLogs (Message) values (concat('No table found for Member ID', member_id, '. FAILED!!'));
	  END IF;
END IF;
END //
DELIMITER ;

-- Trigger change status of table to occupied and booking
DROP TRIGGER IF EXISTS update_table_status_after_booking;
DELIMITER //
CREATE TRIGGER update_table_status_after_booking AFTER INSERT ON bookings
FOR EACH ROW
BEGIN
    UPDATE TableStatus SET booking_id = NEW.booking_id, status = 'Occupied' WHERE table_id = NEW.table_id AND slot_id BETWEEN NEW.start_time_slot AND NEW.start_time_slot + NEW.booking_duration - 1;
    INSERT INTO BookingStatus (booking_id, booking_status) VALUES (NEW.booking_id, 'scheduled');
END//
DELIMITER ;


-- Procedure to cancel a booking 
DROP PROCEDURE IF EXISTS CancelBooking;
DELIMITER //
CREATE PROCEDURE CancelBooking(IN booking_id_param INT)
BEGIN
    DECLARE penalty FLOAT;
    DECLARE current_status enum('scheduled','ongoing', 'completed', 'cancelled');
    IF EXISTS (SELECT 1 FROM Bookings WHERE booking_id = booking_id_param) THEN
		select booking_status INTO current_status from bookingstatus where booking_id=booking_id_param;
        IF current_status = 'scheduled' THEN
			UPDATE BookingStatus SET booking_status = 'cancelled', cancelled_on = CURRENT_TIMESTAMP WHERE booking_id = booking_id_param;
			UPDATE TableStatus SET booking_id=NULL, status='Vacant' WHERE booking_id = booking_id_param; 
			SELECT cancellation_penalty INTO penalty FROM members JOIN bookings ON members.member_id = bookings.member_id WHERE booking_id = booking_id_param;
			UPDATE Members SET cancellation_penalty = penalty + 2 WHERE member_id = (SELECT member_id FROM bookings WHERE booking_id = booking_id_param);
			SELECT 'Order cancelled successfully.' AS Message;
            INSERT INTO ProgramLogs (Message) values (concat('Booking ID ', booking_id_param, ' by member ID ',(SELECT member_id FROM bookings WHERE booking_id = booking_id_param), ' is CANCELLED!!'));
        ELSE
			 SELECT 'Order cancellation not allowed.' AS Message, booking_id_param as BookingID, current_status;
             INSERT INTO ProgramLogs (Message) values (concat('Booking ID ', booking_id_param, ' by member ID ',(SELECT member_id FROM bookings WHERE booking_id = booking_id_param), ' tried cancelling. FAILED!!'));
		END IF;
    ELSE
        SELECT 'Order does not exist.' AS Message, booking_id_param as BookingID;
        INSERT INTO ProgramLogs (Message) values (concat('Booking ID ', booking_id_param,  ' does not eexist and cannot be cancelled. FAILED!!'));
    END IF;
END//
DELIMITER ;

-- Function to assign a waiter to customer when he checks in. Equally distributes the work load among the waiters.
DROP FUNCTION IF EXISTS GetBookingEmployeeID;
DELIMITER //
CREATE FUNCTION GetBookingEmployeeID(booking_id_param INT) 
RETURNS INT
DETERMINISTIC 
BEGIN
    DECLARE emp_id INT;
    SELECT ws.employee_id INTO emp_id FROM WorkShifts ws 
    WHERE ws.restaurant_id = (SELECT restaurant_id FROM Bookings WHERE booking_id = booking_id_param)
        AND ws.start_time_slot <= (SELECT start_time_slot FROM Bookings WHERE booking_id = booking_id_param)
    ORDER BY (SELECT COUNT(*) FROM bookingstatus WHERE booking_status = 'Ongoing' AND employee_id = ws.employee_id GROUP BY employee_id) LIMIT 1;
  RETURN emp_id;
END//
DELIMITER ;

-- Procedure to check in a customer
DROP PROCEDURE IF EXISTS MemberIn;
DELIMITER //
CREATE PROCEDURE MemberIN(IN mbr_id INT)
BEGIN
  DECLARE bkg_id INT;
  DECLARE bkg_status INT;
  
  SELECT Bookings.booking_id into bkg_id FROM Bookings JOIN bookingstatus ON Bookings.booking_id = bookingstatus.booking_id 
  WHERE Bookings.member_id = mbr_id AND bookingstatus.booking_status = 'Scheduled' ORDER BY Bookings.booking_id DESC LIMIT 1;
  
  IF bkg_id IS NOT NULL THEN
      UPDATE bookingstatus SET booking_status = 'Ongoing', employee_id = GetBookingEmployeeID(bkg_id) WHERE booking_id = bkg_id;
      SELECT mbr_id as MemberID, 'has checked-in.' as Message, bkg_id as BookingID;
      INSERT INTO ProgramLogs (Message) values (concat('Member ID ', mbr_id, ' with booking ID ', bkg_id, ' has checked in. SUCCESS!!'));
  ELSE
    SELECT 'No scheduled booking found for member ID' as Message, mbr_id as MemberID;
     INSERT INTO ProgramLogs (Message) values (concat('Member ID ', mbr_id, ' with no booking tried checking in. FAILED!!'));
  END IF;
END //
DELIMITER ;


-- procedure to check out a customer 
DROP PROCEDURE IF EXISTS MemberOut;
delimiter //
create procedure MemberOut(IN mbr_id INT)
BEGIN
	declare bkg_id INT;
    select Bookings.booking_id into bkg_id from Bookings join bookingstatus on Bookings.booking_id=bookingstatus.booking_id where Bookings.member_id=mbr_id and bookingstatus.booking_status='Ongoing' order by Bookings.booking_id desc limit 1;
    IF bkg_id IS NOT NULL THEN
		update bookingstatus set booking_status='completed' where booking_id=bkg_id;
		update tablestatus set status='Vacant' where booking_id=bkg_id;
        INSERT INTO ProgramLogs (Message) values (concat('Member ID ', mbr_id, ' with booking ID ', bkg_id, ' has checked out. SUCCESS!!'));
        
    else
		SELECT mbr_id, ' has not checked in.';
        INSERT INTO ProgramLogs (Message) values (concat('Member ID ', mbr_id, ' with no valid booking tried checking out. FAILED!!'));
	END IF;
END //
delimiter ;


-- Procedure to order food
DROP PROCEDURE IF EXISTS OrderFood;
DELIMITER //
CREATE PROCEDURE OrderFood(IN booking_id_param INT, IN MenuItem_id_param INT, IN qty INT)
begin
	declare brc_id int;
	IF (select booking_status from bookingstatus where booking_id=booking_id_param)='ongoing'  THEN
		select restaurant_id into brc_id from Bookings B where B.booking_id=booking_id_param;
		IF (select availability from restaurantMenu where restaurant_id=brc_id and MenuItem_id=MenuItem_id_param)=TRUE THEN
			insert into Orders (booking_id, MenuItem_id, quantity) values (booking_id_param, MenuItem_id_param, qty);
			select "Order recieved" as Message;            
		ELSE
			select "MenuItem is unavailable";
            INSERT INTO ProgramLogs (Message) values (concat('MenuItem ID ',MenuItem_id_param, ' at restaurant ID ', brc_id, ' was not available for booking ID ',booking_id_param, '. FAILED!!'));
		END IF;
	ELSE
		select "Not a valid Booking ID" as message, booking_id_param as BookingID; 
        INSERT INTO ProgramLogs (Message) values (concat('Booking ID ', booking_id_param, ' which is not a valid tried ordering food. FAILED!!'));
    END IF;    
END //
DELIMITER ;

-- Function to calculate the bill for the ordered items
DELIMITER //
CREATE FUNCTION CalcPriceForBooking(book_id_param INT) RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
	DECLARE total DECIMAL(10,2);
    select sum(C.price*O.quantity) into total  from Orders O join MenuItems C on O.MenuItem_id=C.MenuItem_id where O.booking_id=book_id_param;
	RETURN total;
END//
delimiter ;

-- Function to calculate the tax for the booking
DELIMITER //
CREATE FUNCTION CalcTaxForBooking(booking_id_param INT) RETURNS DECIMAL(10, 2)
READS SQL DATA
BEGIN
    DECLARE tax_amount DECIMAL(10, 2);
    DECLARE tax_rate DECIMAL(3, 2);
    SELECT (CalcPriceForBooking(booking_id_param)*(SELECT tax FROM restaurants WHERE restaurant_id = (SELECT restaurant_id FROM Bookings WHERE booking_id = booking_id_param))/100) into tax_amount;
    RETURN tax_amount;
END//
DELIMITER ;

-- Function to calculate the total price for booking
DELIMITER //
CREATE FUNCTION CalcPriceAfterTax(book_id_param INT) RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE Total DECIMAL(10,2);
    SELECT (CalcPriceForBooking(book_id_param)+CalcTaxForBooking(book_id_param)) INTO Total;
    RETURN Total;
END//
DELIMITER ;

-- Tigger to updata the billing table when a dish is ordered
delimiter //
create trigger  UpdateBillingTable after insert on Orders
FOR EACH ROW
BEGIN
	insert into billing (order_id, total_amount) values (new.Order_id, (new.quantity*(select price from MenuItems where MenuItem_id=new.MenuItem_id)));
END //
delimiter ;

-- Trigger to update the billing status when a customer checks out 
drop trigger if exists UpdateAfterBookigComplete;
delimiter //
create trigger UpdateAfterBookigComplete after update on BookingStatus 
for each row
begin
	IF old.booking_status='ongoing' and new.booking_status='completed' then
		insert into PastBookings (booking_id, total_price, total_price_after_tax,total_tax) values (old.booking_id, CalcPriceForBooking(old.booking_id), CalcPriceAfterTax(old.booking_id), CalcTaxForBooking(old.booking_id));
        update billing set payment_status='paid' where order_id in (select order_id from Orders where booking_id=old.booking_id);
    end if;
end //
delimiter ;



-- Data Entry


INSERT INTO restaurants (restaurant_name, location, zip_code, phone_number, email, tax) 
VALUES 
('Main Street Grill', '123 Main St', '12345', '555-123-4567', 'mainstreet@example.com', 8.5),
('Downtown Bistro', '456 Elm St', '23456', '555-234-5678', 'downtownbistro@example.com', 9.0),
('Parkside Cafe', '789 Oak St', '34567', '555-345-6789', 'parksidecafe@example.com', 8.0),
('City Diner', '1010 Maple Ave', '45678', '555-456-7890', 'citydiner@example.com', 8.2),
('Sunset Grill', '1313 Pine St', '56789', '555-567-8901', 'sunsetgrill@example.com', 7.5),
('Ocean View Restaurant', '1414 Beach Blvd', '67890', '555-678-9012', 'oceanview@example.com', 8.8),
('Mountain Eats', '1515 Summit Ave', '78901', '555-789-0123', 'mountaineats@example.com', 9.5),
('Riverside Cafe', '1616 River Rd', '89012', '555-890-1234', 'riversidecafe@example.com', 8.3),
('Lakefront Bistro', '1717 Lakeview Dr', '90123', '555-901-2345', 'lakefrontbistro@example.com', 7.9),
('Harbor House', '1818 Harbor St', '01234', '555-012-3456', 'harborhouse@example.com', 8.7),
('Marketplace Eatery', '1919 Market St', '12345', '555-123-4567', 'marketplace@example.com', 7.8),
('Countryside Cafe', '2020 Meadow Ln', '23456', '555-234-5678', 'countrysidecafe@example.com', 8.6),
('Central Bistro', '2121 Central Ave', '34567', '555-345-6789', 'centralbistro@example.com', 8.1),
('Bayside Grill', '2222 Bayview Dr', '45678', '555-456-7890', 'baysidegrill@example.com', 9.2),
('Hilltop Diner', '2323 Hillcrest Dr', '56789', '555-567-8901', 'hilltopdiner@example.com', 7.7),
('Highland Restaurant', '2424 Highland Ave', '67890', '555-678-9012', 'highlandrestaurant@example.com', 8.4),
('Parkway Cafe', '2525 Park Ave', '78901', '555-789-0123', 'parkwaycafe@example.com', 9.1),
('Valley View Grill', '2626 Valley Rd', '89012', '555-890-1234', 'valleyview@example.com', 8.9),
('Downtown Deli', '2727 Elm St', '90123', '555-901-2345', 'downtowndeli@example.com', 8.0),
('Country Kitchen', '2828 Country Rd', '01234', '555-012-3456', 'countrykitchen@example.com', 8.7),
('Garden Cafe', '2929 Garden Ave', '12345', '555-123-4567', 'gardencafe@example.com', 8.3),
('Palm Bistro', '3030 Palm St', '23456', '555-234-5678', 'palmbistro@example.com', 9.0),
('Sunrise Restaurant', '3131 Sunrise Blvd', '34567', '555-345-6789', 'sunriserestaurant@example.com', 7.6),
('Meadowside Eatery', '3232 Meadowview Dr', '45678', '555-456-7890', 'meadowside@example.com', 8.5),
('Bayfront Grill', '3333 Bayfront Ave', '56789', '555-567-8901', 'bayfrontgrill@example.com', 8.2),
('Mountain View Cafe', '3434 Mountain Rd', '67890', '555-678-9012', 'mountainview@example.com', 7.8),
('Riverwalk Bistro', '3535 Riverwalk Ln', '78901', '555-789-0123', 'riverwalkbistro@example.com', 8.6),
('Lakeside Diner', '3636 Lakeside Dr', '89012', '555-890-1234', 'lakesidediner@example.com', 8.4),
('Coastal Kitchen', '3737 Coastal Blvd', '90123', '555-901-2345', 'coastalkitchen@example.com', 9.3),
('Cityscape Cafe', '3838 Cityscape St', '01234', '555-012-3456', 'cityscapecafe@example.com', 8.1),
('Ridgeview Restaurant', '3939 Ridgeview Rd', '12345', '555-123-4567', 'ridgeview@example.com', 8.7),
('Seaside Bistro', '4040 Seaside Ave', '23456', '555-234-5678', 'seasidebistro@example.com', 8.2),
('Town Square Grill', '4141 Town Square', '34567', '555-345-6789', 'townsquaregrill@example.com', 7.9),
('Creekview Cafe', '4242 Creekview Dr', '45678', '555-456-7890', 'creekviewcafe@example.com', 8.5),
('Hometown Diner', '4343 Hometown Blvd', '56789', '555-567-8901', 'hometowndiner@example.com', 8.0),
('Wharfside Restaurant', '4444 Wharfside St', '67890', '555-678-9012', 'wharfside@example.com', 9.1),
('Village Kitchen', '4545 Village Ln', '78901', '555-789-0123', 'villagekitchen@example.com', 8.3),
('Grandview Grill', '4646 Grandview Ave', '89012', '555-890-1234', 'grandviewgrill@example.com', 8.6),
('Lakefront Deli', '4747 Lakefront Rd', '90123', '555-901-2345', 'lakefrontdeli@example.com', 7.8),
('Hillside Cafe', '4848 Hillside Dr', '01234', '555-012-3456', 'hillsidecafe@example.com', 8.4),
('Oceanfront Grill', '4848 Oceanfront Ave', '56789', '555-567-8901', 'oceanfrontgrill@example.com', 8.9),
('Riverside Bistro', '4949 Riverside Rd', '67890', '555-678-9012', 'riversidebistro@example.com', 8.2),
('Lighthouse Cafe', '5050 Lighthouse Ln', '78901', '555-789-0123', 'lighthousecafe@example.com', 7.7),
('Cityscape Deli', '5151 Cityscape Ave', '89012', '555-890-1234', 'cityscapedeli@example.com', 8.6),
('Country Diner', '5252 Country Blvd', '90123', '555-901-2345', 'countrydiner@example.com', 8.3),
('Mountain Lodge Restaurant', '5353 Mountain Lodge Rd', '01234', '555-012-3456', 'mountainlodge@example.com', 9.0),
('Riverside Grill', '5454 Riverside Ave', '12345', '555-123-4567', 'riversidegrill@example.com', 8.1),
('Downtown Cafe', '5555 Downtown St', '23456', '555-234-5678', 'downtowncafe@example.com', 8.4),
('Harbor View Bistro', '5656 Harbor View Dr', '34567', '555-345-6789', 'harborviewbistro@example.com', 7.8),
('Parkside Deli', '5757 Parkside Blvd', '45678', '555-456-7890', 'parksidedeli@example.com', 8.5);



-- restaurant 1
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(1, 1, 4),
(1, 2, 6),
(1, 3, 4),
(1, 4, 2),
(1, 5, 8),
(1, 6, 6),
(1, 7, 4),
(1, 8, 2),
(1, 9, 8),
(1, 10, 6);

-- restaurant 2
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(2, 1, 6),
(2, 2, 4),
(2, 3, 2),
(2, 4, 6),
(2, 5, 4),
(2, 6, 8),
(2, 7, 6),
(2, 8, 4),
(2, 9, 2),
(2, 10, 6);

-- restaurant 3
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(3, 1, 4),
(3, 2, 6),
(3, 3, 8),
(3, 4, 2),
(3, 5, 4),
(3, 6, 6),
(3, 7, 8),
(3, 8, 4),
(3, 9, 6),
(3, 10, 2);

-- restaurant 4
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(4, 1, 6),
(4, 2, 4),
(4, 3, 2),
(4, 4, 6),
(4, 5, 4),
(4, 6, 8),
(4, 7, 6),
(4, 8, 4),
(4, 9, 2),
(4, 10, 6);

-- restaurant 5
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(5, 1, 4),
(5, 2, 6),
(5, 3, 4),
(5, 4, 2),
(5, 5, 8),
(5, 6, 6),
(5, 7, 4),
(5, 8, 2),
(5, 9, 8),
(5, 10, 6);

-- restaurant 6
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(6, 1, 4),
(6, 2, 6),
(6, 3, 8),
(6, 4, 2),
(6, 5, 4),
(6, 6, 6),
(6, 7, 8),
(6, 8, 4),
(6, 9, 6),
(6, 10, 2);

-- restaurant 7
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(7, 1, 6),
(7, 2, 4),
(7, 3, 8),
(7, 4, 2),
(7, 5, 6),
(7, 6, 4),
(7, 7, 8),
(7, 8, 2),
(7, 9, 4),
(7, 10, 6);

-- restaurant 8
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(8, 1, 4),
(8, 2, 6),
(8, 3, 4),
(8, 4, 8),
(8, 5, 2),
(8, 6, 6),
(8, 7, 4),
(8, 8, 2),
(8, 9, 8),
(8, 10, 6);

-- restaurant 9
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(9, 1, 6),
(9, 2, 4),
(9, 3, 2),
(9, 4, 6),
(9, 5, 8),
(9, 6, 4),
(9, 7, 2),
(9, 8, 6),
(9, 9, 8),
(9, 10, 6);

-- restaurant 10
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(10, 1, 4),
(10, 2, 6),
(10, 3, 8),
(10, 4, 2),
(10, 5, 4),
(10, 6, 6),
(10, 7, 8),
(10, 8, 4),
(10, 9, 6),
(10, 10, 2);

-- restaurant 11
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(11, 1, 4),
(11, 2, 6),
(11, 3, 8),
(11, 4, 2),
(11, 5, 4),
(11, 6, 6),
(11, 7, 8),
(11, 8, 4),
(11, 9, 6),
(11, 10, 2);

-- restaurant 12
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(12, 1, 6),
(12, 2, 4),
(12, 3, 2),
(12, 4, 6),
(12, 5, 8),
(12, 6, 4),
(12, 7, 2),
(12, 8, 6),
(12, 9, 8),
(12, 10, 6);

-- restaurant 13
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(13, 1, 4),
(13, 2, 6),
(13, 3, 8),
(13, 4, 2),
(13, 5, 4),
(13, 6, 6),
(13, 7, 8),
(13, 8, 4),
(13, 9, 6),
(13, 10, 2);

-- restaurant 14
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(14, 1, 6),
(14, 2, 4),
(14, 3, 2),
(14, 4, 6),
(14, 5, 8),
(14, 6, 4),
(14, 7, 2),
(14, 8, 6),
(14, 9, 8),
(14, 10, 6);

-- restaurant 15
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(15, 1, 4),
(15, 2, 6),
(15, 3, 8),
(15, 4, 2),
(15, 5, 4),
(15, 6, 6),
(15, 7, 8),
(15, 8, 4),
(15, 9, 6),
(15, 10, 2);

-- restaurant 16
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(16, 1, 4),
(16, 2, 6),
(16, 3, 8),
(16, 4, 2),
(16, 5, 4),
(16, 6, 6),
(16, 7, 8),
(16, 8, 4),
(16, 9, 6),
(16, 10, 2);

-- restaurant 17
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(17, 1, 6),
(17, 2, 4),
(17, 3, 2),
(17, 4, 6),
(17, 5, 8),
(17, 6, 4),
(17, 7, 2),
(17, 8, 6),
(17, 9, 8),
(17, 10, 6);

-- restaurant 18
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(18, 1, 4),
(18, 2, 6),
(18, 3, 8),
(18, 4, 2),
(18, 5, 4),
(18, 6, 6),
(18, 7, 8),
(18, 8, 4),
(18, 9, 6),
(18, 10, 2);

-- restaurant 19
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(19, 1, 6),
(19, 2, 4),
(19, 3, 2),
(19, 4, 6),
(19, 5, 8),
(19, 6, 4),
(19, 7, 2),
(19, 8, 6),
(19, 9, 8),
(19, 10, 6);

-- restaurant 20
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(20, 1, 4),
(20, 2, 6),
(20, 3, 8),
(20, 4, 2),
(20, 5, 4),
(20, 6, 6),
(20, 7, 8),
(20, 8, 4),
(20, 9, 6),
(20, 10, 2);

-- restaurant 21
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(21, 1, 4),
(21, 2, 6),
(21, 3, 8),
(21, 4, 2),
(21, 5, 4),
(21, 6, 6),
(21, 7, 8),
(21, 8, 4),
(21, 9, 6),
(21, 10, 2);

-- restaurant 22
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(22, 1, 6),
(22, 2, 4),
(22, 3, 2),
(22, 4, 6),
(22, 5, 8),
(22, 6, 4),
(22, 7, 2),
(22, 8, 6),
(22, 9, 8),
(22, 10, 6);

-- restaurant 23
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(23, 1, 4),
(23, 2, 6),
(23, 3, 8),
(23, 4, 2),
(23, 5, 4),
(23, 6, 6),
(23, 7, 8),
(23, 8, 4),
(23, 9, 6),
(23, 10, 2);

-- restaurant 24
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(24, 1, 6),
(24, 2, 4),
(24, 3, 2),
(24, 4, 6),
(24, 5, 8),
(24, 6, 4),
(24, 7, 2),
(24, 8, 6),
(24, 9, 8),
(24, 10, 6);

-- restaurant 25
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(25, 1, 4),
(25, 2, 6),
(25, 3, 8),
(25, 4, 2),
(25, 5, 4),
(25, 6, 6),
(25, 7, 8),
(25, 8, 4),
(25, 9, 6),
(25, 10, 2);

-- restaurant 26
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(26, 1, 4),
(26, 2, 6),
(26, 3, 8),
(26, 4, 2),
(26, 5, 4),
(26, 6, 6),
(26, 7, 8),
(26, 8, 4),
(26, 9, 6),
(26, 10, 2);

-- restaurant 27
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(27, 1, 6),
(27, 2, 4),
(27, 3, 2),
(27, 4, 6),
(27, 5, 8),
(27, 6, 4),
(27, 7, 2),
(27, 8, 6),
(27, 9, 8),
(27, 10, 6);

-- restaurant 28
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(28, 1, 4),
(28, 2, 6),
(28, 3, 8),
(28, 4, 2),
(28, 5, 4),
(28, 6, 6),
(28, 7, 8),
(28, 8, 4),
(28, 9, 6),
(28, 10, 2);

-- restaurant 29
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(29, 1, 6),
(29, 2, 4),
(29, 3, 2),
(29, 4, 6),
(29, 5, 8),
(29, 6, 4),
(29, 7, 2),
(29, 8, 6),
(29, 9, 8),
(29, 10, 6);

-- restaurant 30
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(30, 1, 4),
(30, 2, 6),
(30, 3, 8),
(30, 4, 2),
(30, 5, 4),
(30, 6, 6),
(30, 7, 8),
(30, 8, 4),
(30, 9, 6),
(30, 10, 2);

-- restaurant 31
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(31, 1, 4),
(31, 2, 6),
(31, 3, 8),
(31, 4, 2),
(31, 5, 4),
(31, 6, 6),
(31, 7, 8),
(31, 8, 4),
(31, 9, 6),
(31, 10, 2);

-- restaurant 32
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(32, 1, 6),
(32, 2, 4),
(32, 3, 2),
(32, 4, 6),
(32, 5, 8),
(32, 6, 4),
(32, 7, 2),
(32, 8, 6),
(32, 9, 8),
(32, 10, 6);

-- restaurant 33
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(33, 1, 4),
(33, 2, 6),
(33, 3, 8),
(33, 4, 2),
(33, 5, 4),
(33, 6, 6),
(33, 7, 8),
(33, 8, 4),
(33, 9, 6),
(33, 10, 2);

-- restaurant 34
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(34, 1, 6),
(34, 2, 4),
(34, 3, 2),
(34, 4, 6),
(34, 5, 8),
(34, 6, 4),
(34, 7, 2),
(34, 8, 6),
(34, 9, 8),
(34, 10, 6);

-- restaurant 35
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(35, 1, 4),
(35, 2, 6),
(35, 3, 8),
(35, 4, 2),
(35, 5, 4),
(35, 6, 6),
(35, 7, 8),
(35, 8, 4),
(35, 9, 6),
(35, 10, 2);

-- restaurant 36
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(36, 1, 4),
(36, 2, 6),
(36, 3, 8),
(36, 4, 2),
(36, 5, 4),
(36, 6, 6),
(36, 7, 8),
(36, 8, 4),
(36, 9, 6),
(36, 10, 2);

-- restaurant 37
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(37, 1, 6),
(37, 2, 4),
(37, 3, 2),
(37, 4, 6),
(37, 5, 8),
(37, 6, 4),
(37, 7, 2),
(37, 8, 6),
(37, 9, 8),
(37, 10, 6);

-- restaurant 38
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(38, 1, 4),
(38, 2, 6),
(38, 3, 8),
(38, 4, 2),
(38, 5, 4),
(38, 6, 6),
(38, 7, 8),
(38, 8, 4),
(38, 9, 6),
(38, 10, 2);

-- restaurant 39
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(39, 1, 6),
(39, 2, 4),
(39, 3, 2),
(39, 4, 6),
(39, 5, 8),
(39, 6, 4),
(39, 7, 2),
(39, 8, 6),
(39, 9, 8),
(39, 10, 6);

-- restaurant 40
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(40, 1, 4),
(40, 2, 6),
(40, 3, 8),
(40, 4, 2),
(40, 5, 4),
(40, 6, 6),
(40, 7, 8),
(40, 8, 4),
(40, 9, 6),
(40, 10, 2);

-- restaurant 41
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(41, 1, 4),
(41, 2, 6),
(41, 3, 8),
(41, 4, 2),
(41, 5, 4),
(41, 6, 6),
(41, 7, 8),
(41, 8, 4),
(41, 9, 6),
(41, 10, 2);

-- restaurant 42
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(42, 1, 6),
(42, 2, 4),
(42, 3, 2),
(42, 4, 6),
(42, 5, 8),
(42, 6, 4),
(42, 7, 2),
(42, 8, 6),
(42, 9, 8),
(42, 10, 6);

-- restaurant 43
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(43, 1, 4),
(43, 2, 6),
(43, 3, 8),
(43, 4, 2),
(43, 5, 4),
(43, 6, 6),
(43, 7, 8),
(43, 8, 4),
(43, 9, 6),
(43, 10, 2);

-- restaurant 44
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(44, 1, 6),
(44, 2, 4),
(44, 3, 2),
(44, 4, 6),
(44, 5, 8),
(44, 6, 4),
(44, 7, 2),
(44, 8, 6),
(44, 9, 8),
(44, 10, 6);

-- restaurant 45
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(45, 1, 4),
(45, 2, 6),
(45, 3, 8),
(45, 4, 2),
(45, 5, 4),
(45, 6, 6),
(45, 7, 8),
(45, 8, 4),
(45, 9, 6),
(45, 10, 2);

-- restaurant 46
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(46, 1, 4),
(46, 2, 6),
(46, 3, 8),
(46, 4, 2),
(46, 5, 4),
(46, 6, 6),
(46, 7, 8),
(46, 8, 4),
(46, 9, 6),
(46, 10, 2);

-- restaurant 47
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(47, 1, 6),
(47, 2, 4),
(47, 3, 2),
(47, 4, 6),
(47, 5, 8),
(47, 6, 4),
(47, 7, 2),
(47, 8, 6),
(47, 9, 8),
(47, 10, 6);

-- restaurant 48
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(48, 1, 4),
(48, 2, 6),
(48, 3, 8),
(48, 4, 2),
(48, 5, 4),
(48, 6, 6),
(48, 7, 8),
(48, 8, 4),
(48, 9, 6),
(48, 10, 2);

-- restaurant 49
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(49, 1, 6),
(49, 2, 4),
(49, 3, 2),
(49, 4, 6),
(49, 5, 8),
(49, 6, 4),
(49, 7, 2),
(49, 8, 6),
(49, 9, 8),
(49, 10, 6);

-- restaurant 50
INSERT INTO RTables (restaurant_id, table_number, capacity) VALUES
(50, 1, 4),
(50, 2, 6),
(50, 3, 8),
(50, 4, 2),
(50, 5, 4),
(50, 6, 6),
(50, 7, 8),
(50, 8, 4),
(50, 9, 6),
(50, 10, 2);


-- Query 2
-- Insert default table status at the start of the day
INSERT INTO TableStatus (table_id, slot_id, status)
  SELECT t.table_id, ts.slot_id, 'Vacant'
  FROM RTables t
  CROSS JOIN time_slots ts;



INSERT INTO Employees (employee_name, phone_number, email, username, password, role) VALUES
('John Smith', '123-456-7890', 'john_smith@example.com', 'john_smith', 'password1', 'chef'),
('Sarah Johnson', '987-654-3210', 'sarah_johnson@example.com', 'sarah_johnson', 'password2', 'server'),
('Michael Davis', '555-123-4567', 'michael_davis@example.com', 'michael_davis', 'password3', 'server'),
('Emily Brown', '444-987-6543', 'emily_brown@example.com', 'emily_brown', 'password4', 'manager'),
('Christopher Wilson', '123-456-7890', 'christopher_wilson@example.com', 'christopher_wilson', 'password5', 'chef'),
('Jessica Martinez', '987-654-3210', 'jessica_martinez@example.com', 'jessica_martinez', 'password6', 'server'),
('Matthew Taylor', '555-123-4567', 'matthew_taylor@example.com', 'matthew_taylor', 'password7', 'server'),
('Amanda Anderson', '444-987-6543', 'amanda_anderson@example.com', 'amanda_anderson', 'password8', 'manager'),
('David Thomas', '123-456-7890', 'david_thomas@example.com', 'david_thomas', 'password9', 'chef'),
('Megan White', '987-654-3210', 'megan_white@example.com', 'megan_white', 'password10', 'server'),
('James Garcia', '555-123-4567', 'james_garcia@example.com', 'james_garcia', 'password11', 'server'),
('Ashley Martinez', '444-987-6543', 'ashley_martinez@example.com', 'ashley_martinez', 'password12', 'manager'),
('Robert Johnson', '123-456-7890', 'robert_johnson@example.com', 'robert_johnson', 'password13', 'chef'),
('Jennifer Brown', '987-654-3210', 'jennifer_brown@example.com', 'jennifer_brown', 'password14', 'server'),
('William Rodriguez', '555-123-4567', 'william_rodriguez@example.com', 'william_rodriguez', 'password15', 'server'),
('Elizabeth Wilson', '444-987-6543', 'elizabeth_wilson@example.com', 'elizabeth_wilson', 'password16', 'manager'),
('Charles Smith', '123-456-7890', 'charles_smith@example.com', 'charles_smith', 'password17', 'chef'),
('Margaret Johnson', '987-654-3210', 'margaret_johnson@example.com', 'margaret_johnson', 'password18', 'server'),
('Joseph Martinez', '555-123-4567', 'joseph_martinez@example.com', 'joseph_martinez', 'password19', 'server'),
('Samantha Taylor', '444-987-6543', 'samantha_taylor@example.com', 'samantha_taylor', 'password20', 'manager'),
('Daniel Davis', '123-456-7890', 'daniel_davis@example.com', 'daniel_davis', 'password21', 'chef'),
('Patricia White', '987-654-3210', 'patricia_white@example.com', 'patricia_white', 'password22', 'server'),
('Christopher Brown', '555-123-4567', 'christopher_brown@example.com', 'christopher_brown', 'password23', 'server'),
('Brittany Martinez', '444-987-6543', 'brittany_martinez@example.com', 'brittany_martinez', 'password24', 'manager'),
('Andrew Johnson', '123-456-7890', 'andrew_johnson@example.com', 'andrew_johnson', 'password25', 'chef'),
('Laura Garcia', '987-654-3210', 'laura_garcia@example.com', 'laura_garcia', 'password26', 'server'),
('Ryan Wilson', '555-123-4567', 'ryan_wilson@example.com', 'ryan_wilson', 'password27', 'server'),
('Alyssa Brown', '444-987-6543', 'alyssa_brown@example.com', 'alyssa_brown', 'password28', 'manager'),
('Nicholas Smith', '123-456-7890', 'nicholas_smith@example.com', 'nicholas_smith', 'password29', 'chef'),
('Kayla Johnson', '987-654-3210', 'kayla_johnson@example.com', 'kayla_johnson', 'password30', 'server'),
('Justin Martinez', '555-123-4567', 'justin_martinez@example.com', 'justin_martinez', 'password31', 'server'),
('Victoria Taylor', '444-987-6543', 'victoria_taylor@example.com', 'victoria_taylor', 'password32', 'manager'),
('Matthew Anderson', '123-456-7890', 'matthew_anderson@example.com', 'matthew_anderson', 'password33', 'chef'),
('Hannah Garcia', '987-654-3210', 'hannah_garcia@example.com', 'hannah_garcia', 'password34', 'server'),
('Tyler Davis', '555-123-4567', 'tyler_davis@example.com', 'tyler_davis', 'password35', 'server'),
('Madison White', '444-987-6543', 'madison_white@example.com', 'madison_white', 'password36', 'manager'),
('Ethan Wilson', '123-456-7890', 'ethan_wilson@example.com', 'ethan_wilson', 'password37', 'chef'),
('Olivia Johnson', '987-654-3210', 'olivia_johnson@example.com', 'olivia_johnson', 'password38', 'server'),
('Andrew Martinez', '555-123-4567', 'andrew_martinez@example.com', 'andrew_martinez', 'password39', 'server'),
('Chloe Taylor', '444-987-6543', 'chloe_taylor@example.com', 'chloe_taylor', 'password40', 'manager'),
('William Brown', '123-456-7890', 'william_brown@example.com', 'william_brown', 'password41', 'chef'),
('Sophia Smith', '987-654-3210', 'sophia_smith@example.com', 'sophia_smith', 'password42', 'server'),
('Ella Martinez', '444-987-6543', 'ella_martinez@example.com', 'ella_martinez', 'password43', 'manager'),
('Jacob Brown', '123-456-7890', 'jacob_brown@example.com', 'jacob_brown', 'password44', 'chef'),
('Grace Wilson', '987-654-3210', 'grace_wilson@example.com', 'grace_wilson', 'password45', 'server'),
('Logan Johnson', '555-123-4567', 'logan_johnson@example.com', 'logan_johnson', 'password46', 'server'),
('Avery Taylor', '444-987-6543', 'avery_taylor@example.com', 'avery_taylor', 'password47', 'manager'),
('Natalie Garcia', '123-456-7890', 'natalie_garcia@example.com', 'natalie_garcia', 'password48', 'chef'),
('Carter Smith', '987-654-3210', 'carter_smith@example.com', 'carter_smith', 'password49', 'server'),
('Addison Davis', '555-123-4567', 'addison_davis@example.com', 'addison_davis', 'password50', 'server');

INSERT INTO Employees (employee_name, phone_number, email, username, password, role) VALUES
('John Smithle', '123-456-7890', 'john@example.com', 'johns', 'password123', 'server'),
('Alice Johnsonle', '456-789-0123', 'alice@example.com', 'alicej', 'pass123', 'server'),
('Michael Brownle', '789-012-3456', 'michael@example.com', 'michaelb', 'abc123', 'server'),
('Emily Davisle', '012-345-6789', 'emily@example.com', 'emilyd', 'xyz456', 'server'),
('David Wilsonle', '345-678-9012', 'david@example.com', 'davidw', 'qwerty', 'server'),
('Sarah Martinezle', '678-901-2345', 'sarah@example.com', 'sarahm', '123abc', 'server'),
('Robert Andersonle', '901-234-5678', 'robert@example.com', 'robertr', 'passpass', 'server'),
('Jennifer Taylorle', '234-567-8901', 'jennifer@example.com', 'jennifert', 'letmein', 'server'),
('James Thomasle', '567-890-1234', 'james@example.com', 'jamest', 'password', 'server'),
('Jessica Hernandezle', '890-123-4567', 'jessica@example.com', 'jessicah', 'abc123', 'server'),
('Daniel Gonzalezle', '123-456-7890', 'daniel@example.com', 'danield', 'password123', 'server'),
('Linda Rodriguezle', '456-789-0123', 'linda@example.com', 'lindar', 'pass123', 'server'),
('Christopher Leele', '789-012-3456', 'christopher@example.com', 'christopherl', 'abc123', 'server'),
('Amanda Walkerle', '012-345-6789', 'amanda@example.com', 'amandaw', 'xyz456', 'server'),
('Matthew Hallle', '345-678-9012', 'matthew@example.com', 'matthewh', 'qwerty', 'server'),
('Ashley Youngle', '678-901-2345', 'ashley@example.com', 'ashleyy', '123abc', 'server'),
('Joshua Kingle', '901-234-5678', 'joshua@example.com', 'joshuak', 'passpass', 'server'),
('Megan Scottle', '234-567-8901', 'megan@example.com', 'megans', 'letmein', 'server'),
('Ryan Greenle', '567-890-1234', 'ryan@example.com', 'ryang', 'password', 'server'),
('Olivia Bakerle', '890-123-4567', 'olivia@example.com', 'oliviab', 'abc123', 'server');

INSERT INTO Members (customer_id, username, password_hash, first_name, last_name, email, phone_number, login_method, member_status, cancellation_penalty)
VALUES
(1, 'john_smith', 'hash1', 'John', 'Smith', 'john_smith@example.com', '123-456-7890', 'Website', 'Active', 0),
(2, 'sarah_johnson', 'hash2', 'Sarah', 'Johnson', 'sarah_johnson@example.com', '234-567-8901', 'Walk-in', 'Active', 0),
(3, 'michael_davis', 'hash3', 'Michael', 'Davis', 'michael_davis@example.com', '345-678-9012', 'Phone Call', 'Just Member', 0),
(4, 'emily_brown', 'hash4', 'Emily', 'Brown', 'emily_brown@example.com', '456-789-0123', 'Website', 'Cancelled', 25.00),
(5, 'chris_wilson', 'hash5', 'Christopher', 'Wilson', 'chris_wilson@example.com', '567-890-1234', 'Walk-in', 'Active', 0),
(6, 'jessica_martinez', 'hash6', 'Jessica', 'Martinez', 'jessica_martinez@example.com', '678-901-2345', 'Website', 'Just Member', 0),
(7, 'matthew_taylor', 'hash7', 'Matthew', 'Taylor', 'matthew_taylor@example.com', '789-012-3456', 'Phone Call', 'Active', 0),
(8, 'amanda_anderson', 'hash8', 'Amanda', 'Anderson', 'amanda_anderson@example.com', '890-123-4567', 'Website', 'Cancelled', 30.00),
(9, 'david_thomas', 'hash9', 'David', 'Thomas', 'david_thomas@example.com', '901-234-5678', 'Phone Call', 'Active', 0),
(10, 'megan_white', 'hash10', 'Megan', 'White', 'megan_white@example.com', '012-345-6789', 'Website', 'Just Member', 0),
(11, 'james_garcia', 'hash11', 'James', 'Garcia', 'james_garcia@example.com', '111-222-3333', 'Walk-in', 'Active', 0),
(12, 'ashley_martinez', 'hash12', 'Ashley', 'Martinez', 'ashley_martinez@example.com', '222-333-4444', 'Phone Call', 'Cancelled', 35.00),
(13, 'robert_johnson', 'hash13', 'Robert', 'Johnson', 'robert_johnson@example.com', '333-444-5555', 'Website', 'Active', 0),
(14, 'jennifer_brown', 'hash14', 'Jennifer', 'Brown', 'jennifer_brown@example.com', '444-555-6666', 'Walk-in', 'Just Member', 0),
(15, 'william_rodriguez', 'hash15', 'William', 'Rodriguez', 'william_rodriguez@example.com', '555-666-7777', 'Phone Call', 'Active', 0),
(16, 'elizabeth_wilson', 'hash16', 'Elizabeth', 'Wilson', 'elizabeth_wilson@example.com', '666-777-8888', 'Website', 'Cancelled', 20.00),
(17, 'charles_smith', 'hash17', 'Charles', 'Smith', 'charles_smith@example.com', '777-888-9999', 'Walk-in', 'Active', 0),
(18, 'margaret_johnson', 'hash18', 'Margaret', 'Johnson', 'margaret_johnson@example.com', '888-999-0000', 'Website', 'Just Member', 0),
(19, 'joseph_martinez', 'hash19', 'Joseph', 'Martinez', 'joseph_martinez@example.com', '999-000-1111', 'Phone Call', 'Active', 0),
(20, 'samantha_taylor', 'hash20', 'Samantha', 'Taylor', 'samantha_taylor@example.com', '000-111-2222', 'Website', 'Cancelled', 40.00),
(21, 'daniel_davis', 'hash21', 'Daniel', 'Davis', 'daniel_davis@example.com', '121-222-3333', 'Walk-in', 'Active', 0),
(22, 'patricia_white', 'hash22', 'Patricia', 'White', 'patricia_white@example.com', '242-333-4444', 'Phone Call', 'Just Member', 0),
(23, 'christopher_brown', 'hash23', 'Christopher', 'Brown', 'christopher_brown@example.com', '343-444-5555', 'Website', 'Active', 0),
(24, 'brittany_martinez', 'hash24', 'Brittany', 'Martinez', 'brittany_martinez@example.com', '434-555-6666', 'Walk-in', 'Cancelled', 50.00),
(25, 'olivia_taylor', 'hash25', 'Olivia', 'Taylor', 'olivia_taylor@example.com', '565-666-7777', 'Phone Call', 'Active', 0),
(26, 'ethan_thomas', 'hash26', 'Ethan', 'Thomas', 'ethan_thomas@example.com', '656-777-8888', 'Website', 'Just Member', 0),
(27, 'ava_garcia', 'hash27', 'Ava', 'Garcia', 'ava_garcia@example.com', '787-888-9999', 'Walk-in', 'Active', 0),
(28, 'noah_rodriguez', 'hash28', 'Noah', 'Rodriguez', 'noah_rodriguez@example.com', '878-999-0000', 'Phone Call', 'Just Member', 0),
(29, 'emma_anderson', 'hash29', 'Emma', 'Anderson', 'emma_anderson@example.com', '919-000-1111', 'Website', 'Active', 0),
(30, 'liam_martinez', 'hash30', 'Liam', 'Martinez', 'liam_martinez@example.com', '010-111-2222', 'Walk-in', 'Cancelled', 60.00),
(31, 'ava_davis', 'hash31', 'Ava', 'Davis', 'ava_davis@example.com', '111-212-3333', 'Phone Call', 'Active', 0),
(32, 'oliver_smith', 'hash32', 'Oliver', 'Smith', 'oliver_smith@example.com', '222-323-4444', 'Website', 'Just Member', 0),
(33, 'isabella_johnson', 'hash33', 'Isabella', 'Johnson', 'isabella_johnson@example.com', '333-434-5555', 'Walk-in', 'Active', 0),
(34, 'jacob_martinez', 'hash34', 'Jacob', 'Martinez', 'jacob_martinez@example.com', '444-545-6666', 'Phone Call', 'Just Member', 0),
(35, 'mia_taylor', 'hash35', 'Mia', 'Taylor', 'mia_taylor@example.com', '555-656-7777', 'Website', 'Active', 0),
(36, 'ethan_davis', 'hash36', 'Ethan', 'Davis', 'ethan_davis@example.com', '666-767-8888', 'Walk-in', 'Cancelled', 70.00),
(37, 'ava_martinez', 'hash37', 'Ava', 'Martinez', 'ava_martinez@example.com', '777-878-9999', 'Phone Call', 'Active', 0),
(38, 'william_miller', 'hash38', 'William', 'Miller', 'william_miller@example.com', '888-989-0000', 'Website', 'Just Member', 0),
(39, 'olivia_rodriguez', 'hash39', 'Olivia', 'Rodriguez', 'olivia_rodriguez@example.com', '999-090-1111', 'Walk-in', 'Active', 0),
(40, 'liam_garcia', 'hash40', 'Liam', 'Garcia', 'liam_garcia@example.com', '000-191-2222', 'Phone Call', 'Just Member', 0),
(41, 'sophia_smith', 'hash41', 'Sophia', 'Smith', 'sophia_smith@example.com', '111-222-3331', 'Website', 'Active', 0),
(42, 'jackson_johnson', 'hash42', 'Jackson', 'Johnson', 'jackson_johnson@example.com', '221-333-4444', 'Walk-in', 'Cancelled', 80.00),
(43, 'olivia_anderson', 'hash43', 'Olivia', 'Anderson', 'olivia_anderson@example.com', '331-444-5555', 'Phone Call', 'Active', 0),
(44, 'noah_martinez', 'hash44', 'Noah', 'Martinez', 'noah_martinez@example.com', '444-555-1666', 'Website', 'Just Member', 0),
(45, 'ava_brown', 'hash45', 'Ava', 'Brown', 'ava_brown@example.com', '555-666-7771', 'Walk-in', 'Active', 0),
(46, 'emma_garcia', 'hash46', 'Emma', 'Garcia', 'emma_garcia@example.com', '666-717-8888', 'Phone Call', 'Just Member', 0),
(47, 'liam_davis', 'hash47', 'Liam', 'Davis', 'liam_davis@example.com', '777-888-1999', 'Website', 'Active', 0),
(48, 'olivia_martinez', 'hash48', 'Olivia', 'Martinez', 'olivia_martinez@example.com', '188-999-0000', 'Walk-in', 'Cancelled', 90.00),
(49, 'jacob_taylor', 'hash49', 'Jacob', 'Taylor', 'jacob_taylor@example.com', '999-000-1211', 'Phone Call', 'Active', 0),
(50, 'emma_rodriguez', 'hash50', 'Emma', 'Rodriguez', 'emma_rodriguez@example.com', '000-211-2222', 'Website', 'Just Member', 0);




INSERT INTO MenuItems (MenuItem_name, serving_description, price)
VALUES
('American Burger', 'Classic American burger with lettuce, tomato, onion, and pickles.', 9.99),
('Italian Pizza', 'Thin crust pizza topped with marinara sauce, mozzarella cheese, and pepperoni.', 12.99),
('Mexican Tacos', 'Soft tortillas filled with seasoned beef, lettuce, cheese, and salsa.', 8.99),
('Chinese Stir Fry', 'Fresh vegetables and choice of protein stir-fried in a savory sauce.', 10.99),
('Japanese Sushi', 'Assorted sushi rolls including California roll, spicy tuna roll, and salmon avocado roll.', 14.99),
('Indian Curry', 'Creamy chicken curry served with basmati rice and naan bread.', 11.99),
('Thai Pad Thai', 'Stir-fried rice noodles with tofu, shrimp, egg, peanuts, and bean sprouts.', 10.99),
('Mediterranean Falafel', 'Crispy chickpea patties served in a pita with lettuce, tomato, and tahini sauce.', 9.99),
('French Croissant', 'Buttery and flaky croissant served with jam and butter.', 4.99),
('Greek Gyro', 'Grilled lamb or chicken wrapped in pita bread with tzatziki sauce, tomatoes, and onions.', 11.99),
('Spanish Paella', 'Traditional Spanish rice dish cooked with saffron, seafood, and chorizo.', 15.99),
('Korean Bibimbap', 'Mixed rice bowl topped with seasoned vegetables, beef, and a fried egg.', 13.99),
('Vietnamese Pho', 'Beef or chicken noodle soup flavored with herbs and spices, served with bean sprouts and lime.', 10.99),
('Brazilian Feijoada', 'Hearty stew of black beans, pork, and sausage served with rice and collard greens.', 12.99),
('Caribbean Jerk Chicken', 'Spicy marinated chicken grilled to perfection, served with rice and beans.', 11.99),
('German Schnitzel', 'Thinly pounded and breaded pork cutlet served with mashed potatoes and sauerkraut.', 13.99),
('Russian Borscht', 'Hearty beet soup with vegetables and beef, served with sour cream.', 9.99),
('Turkish Kebab', 'Grilled skewers of marinated lamb or chicken served with rice and yogurt sauce.', 12.99),
('Moroccan Tagine', 'Slow-cooked stew with tender meat, vegetables, and aromatic spices, served with couscous.', 14.99),
('Peruvian Ceviche', 'Fresh fish marinated in citrus juices with onions, cilantro, and chili peppers.', 15.99),
('African Jollof Rice', 'Spicy rice dish cooked with tomatoes, peppers, and various spices, served with grilled chicken.', 11.99),
('Australian Meat Pie', 'Individual savory pie filled with minced meat and gravy, served with mashed potatoes.', 8.99),
('Belgian Waffles', 'Light and fluffy waffles served with whipped cream and fresh berries.', 7.99),
('Canadian Poutine', 'French fries topped with cheese curds and smothered in gravy.', 9.99),
('Cuban Sandwich', 'Pressed sandwich with roasted pork, ham, Swiss cheese, pickles, and mustard.', 10.99),
('Danish Smørrebrød', 'Open-faced sandwiches with various toppings such as smoked salmon, pickled herring, and egg salad.', 8.99),
('Dutch Pancakes', 'Thin and large pancakes served with powdered sugar and syrup.', 6.99),
('Egyptian Koshari', 'Layered dish of rice, lentils, pasta, and chickpeas topped with spicy tomato sauce and crispy onions.', 9.99),
('Finnish Salmon Soup', 'Creamy soup made with salmon, potatoes, and leeks, seasoned with dill.', 11.99),
('Hungarian Goulash', 'Hearty stew made with tender beef, onions, and paprika, served with egg noodles.', 12.99),
('Icelandic Lamb Soup', 'Rich soup made with lamb, vegetables, and barley, flavored with thyme.', 13.99),
('Irish Stew', 'Comforting stew made with lamb or beef, potatoes, carrots, and onions, flavored with Guinness stout.', 10.99),
('Albanian Tave Kosi', 'Albanian lamb and yogurt casserole flavored with garlic, dill, and rice.', 12.99),
('Armenian Khorovats', 'Armenian grilled meat skewers marinated in onions, garlic, and spices.', 11.99),
('Azerbaijani Plov', 'Azerbaijani rice pilaf cooked with lamb, dried fruits, and aromatic spices.', 13.99),
('Bahraini Machboos', 'Bahraini rice dish made with spiced meat (chicken, lamb, or fish) and vegetables.', 14.99),
('Bruneian Ambuyat', 'Bruneian dish made with sago starch, typically served with various sauces and side dishes.', 10.99),
('Cambodian Amok', 'Cambodian steamed curry made with fish, coconut milk, kroeung paste, and egg.', 12.99),
('Georgian Khachapuri', 'Georgian cheese-filled bread typically topped with an egg and butter.', 9.99),
('Iranian Chelo Kebab', 'Iranian rice dish served with grilled kebabs (usually lamb or chicken).', 15.99),
('Iraqi Masgouf', 'Iraqi grilled fish marinated in olive oil, spices, and tamarind.', 16.99),
('Israeli Shakshuka', 'Israeli dish of poached eggs in a spicy tomato and pepper sauce.', 10.99),
('Jordanian Mansaf', 'Jordanian dish of lamb cooked in a fermented yogurt sauce, served with rice and almonds.', 17.99),
('Kuwaiti Machboos', 'Kuwaiti spiced rice dish with meat (chicken, lamb, or fish) and vegetables.', 14.99),
('Laotian Larb', 'Laotian salad made with minced meat (usually chicken or pork), herbs, and lime juice.', 11.99),
('Lebanese Kibbeh', 'Lebanese dish made with minced meat (usually lamb or beef), bulgur, and spices.', 12.99),
('Omani Shuwa', 'Omani slow-cooked meat (usually lamb) marinated in spices and cooked in an underground oven.', 18.99),
('Palestinian Musakhan', 'Palestinian dish of roasted chicken with sumac, onions, pine nuts, and flatbread.', 13.99),
('Qatari Machboos', 'Qatari spiced rice dish with meat (usually chicken, lamb, or fish) and vegetables.', 14.99),
('Lithuanian Cepelinai', 'Lithuanian dumplings made from grated potatoes and stuffed with meat, usually served with sour cream.', 12.99);


INSERT INTO workshifts (employee_id, restaurant_id, start_time_slot, shift_duration)
VALUES
(1, 1, 1, 10),
(2, 2, 1, 10),
(3, 3, 1, 10),
(4, 4, 1, 10),
( 5, 5, 1, 10),
( 6, 6, 1, 10),
( 7, 7, 1, 10),
( 8, 8, 1, 10),
( 9, 9, 1, 10),
( 10, 10, 1, 10),
(11, 1, 1, 10),
( 12, 2, 1, 10),
( 13, 3, 1, 10),
( 14, 4, 1, 10),
( 15, 5, 1, 10),
( 16, 6, 1, 9),
( 17, 7, 1, 9),
( 18, 8, 1, 9),
( 19, 9, 1, 9),
( 20, 10, 1, 9),
( 21, 1, 1, 9),
( 22, 2, 1, 9),
( 23, 3, 1, 9),
( 24, 4, 1, 9),
( 25, 5, 1, 9),
( 26, 6, 1, 9),
(27, 7, 1, 9),
( 28, 8, 1, 9),
( 29, 9, 1, 9),
( 30, 10, 1, 9),
( 31, 1, 1, 9),
( 32, 2, 1, 9),
( 33, 3, 1, 9),
( 34, 4, 1, 9),
( 35, 5, 1, 9),
( 36, 6, 1, 9),
( 37, 7, 1, 9),
( 38, 8, 1, 9),
( 39, 9, 2, 9),
( 40, 10, 2, 9),
( 41, 10, 2, 9),
( 42, 1, 2, 9),
( 43, 2, 2, 9),
( 44, 3, 2, 9),
( 45, 4, 2, 9),
( 46, 5, 2, 9),
( 47, 6, 2, 9),
( 48, 7, 2, 9),
( 49, 8, 2, 9),
( 50, 9, 2, 9);

select * from restaurantmenu;
truncate restaurantmenu;
INSERT INTO restaurantMenu (restaurant_id, MenuItem_id, availability) VALUES
(1, 1, FALSE),
(1, 2, TRUE),
(1, 3, TRUE),
(1, 4, TRUE),
(1, 5, FALSE),
(1, 6, TRUE),
(1, 7, TRUE),
(1, 8, TRUE),
(1, 9, TRUE),
(1, 10, TRUE),
(1, 11, TRUE),
(1, 12, TRUE),
(1, 13, TRUE),
(1, 14, TRUE),
(1, 15, FALSE),
(1, 16, TRUE),
(1, 17, TRUE),
(1, 18, TRUE),
(1, 19, TRUE),
(1, 20, TRUE),
(1, 21, TRUE),
(1, 22, TRUE),
(1, 23, TRUE),
(1, 24, TRUE),
(1, 25, TRUE),
(1, 26, TRUE),
(1, 27, FALSE),
(1, 28, TRUE),
(1, 29, TRUE),
(1, 30, TRUE),
(2, 1, TRUE),
(2, 2, FALSE),
(2, 3, TRUE),
(2, 4, TRUE),
(2, 5, TRUE),
(2, 6, TRUE),
(2, 7, TRUE),
(2, 8, FALSE),
(2, 9, TRUE),
(2, 10, TRUE),
(2, 11, TRUE),
(2, 12, TRUE),
(2, 13, FALSE),
(2, 14, TRUE),
(2, 15, TRUE),
(2, 16, TRUE),
(2, 17, TRUE),
(2, 18, TRUE),
(2, 19, TRUE),
(2, 20, TRUE),
(2, 21, FALSE),
(2, 22, TRUE),
(2, 23, TRUE),
(2, 24, TRUE),
(2, 25, FALSE),
(2, 26, TRUE),
(2, 27, TRUE),
(2, 28, TRUE),
(2, 29, TRUE),
(2, 30, TRUE),
(3, 11, TRUE),
(3, 12, TRUE),
(3, 13, TRUE),
(3, 14, TRUE),
(3, 15, TRUE),
(3, 16, TRUE),
(3, 17, TRUE),
(3, 18, FALSE),
(3, 19, TRUE),
(3, 20, TRUE),
(3, 21, TRUE),
(3, 22, TRUE),
(3, 23, TRUE),
(3, 24, TRUE),
(3, 25, TRUE),
(3, 26, TRUE),
(3, 27, TRUE),
(3, 28, TRUE),
(3, 29, TRUE),
(3, 30, TRUE),
(3, 31, TRUE),
(3, 32, TRUE),
(3, 33, TRUE),
(3, 34, TRUE),
(3, 35, TRUE),
(3, 36, TRUE),
(3, 37, TRUE),
(3, 38, TRUE),
(3, 39, TRUE),
(3, 40, TRUE),
(4, 11, TRUE),
(4, 12, TRUE),
(4, 13, TRUE),
(4, 14, TRUE),
(4, 15, TRUE),
(4, 16, TRUE),
(4, 17, TRUE),
(4, 18, TRUE),
(4, 19, FALSE),
(4, 20, TRUE),
(4, 21, TRUE),
(4, 22, TRUE),
(4, 23, TRUE),
(4, 24, TRUE),
(4, 25, TRUE),
(4, 26, TRUE),
(4, 27, TRUE),
(4, 28, TRUE),
(4, 29, TRUE),
(4, 30, TRUE),
(4, 31, TRUE),
(4, 32, TRUE),
(4, 33, TRUE),
(4, 34, TRUE),
(4, 35, TRUE),
(4, 36, TRUE),
(4, 37, TRUE),
(4, 38, TRUE),
(4, 39, FALSE),
(4, 40, TRUE),
(	5	,	1	,	TRUE	),
(	5	,	2	,	TRUE	),
(	5	,	3	,	TRUE	),
(	5	,	4	,	TRUE	),
(	5	,	5	,	TRUE	),
(	5	,	6	,	TRUE	),
(	5	,	7	,	FALSE	),
(	5	,	8	,	TRUE	),
(	5	,	9	,	TRUE	),
(	5	,	10	,	TRUE	),
(	5	,	11	,	TRUE	),
(	5	,	12	,	TRUE	),
(	5	,	13	,	TRUE	),
(	5	,	14	,	TRUE	),
(	5	,	15	,	TRUE	),
(	5	,	16	,	TRUE	),
(	5	,	17	,	FALSE	),
(	5	,	18	,	TRUE	),
(	5	,	19	,	TRUE	),
(	5	,	20	,	TRUE	),
(	5	,	21	,	TRUE	),
(	5	,	22	,	TRUE	),
(	5	,	23	,	TRUE	),
(	5	,	24	,	TRUE	),
(	5	,	25	,	TRUE	),
(	5	,	26	,	TRUE	),
(	5	,	27	,	TRUE	),
(	5	,	28	,	TRUE	),
(	5	,	29	,	TRUE	),
(	5	,	30	,	TRUE	),
(	5	,	31	,	TRUE	),
(	6	,	1	,	TRUE	),
(	6	,	2	,	TRUE	),
(	6	,	3	,	TRUE	),
(	6	,	4	,	TRUE	),
(	6	,	5	,	TRUE	),
(	6	,	6	,	TRUE	),
(	6	,	7	,	TRUE	),
(	6	,	8	,	TRUE	),
(	6	,	9	,	TRUE	),
(	6	,	10	,	TRUE	),
(	6	,	11	,	TRUE	),
(	6	,	12	,	TRUE	),
(	6	,	13	,	TRUE	),
(	6	,	14	,	TRUE	),
(	6	,	15	,	TRUE	),
(	6	,	16	,	TRUE	),
(	6	,	17	,	FALSE	),
(	6	,	18	,	TRUE	),
(	6	,	19	,	TRUE	),
(	6	,	20	,	TRUE	),
(	6	,	21	,	TRUE	),
(	6	,	22	,	TRUE	),
(	6	,	23	,	TRUE	),
(	6	,	24	,	TRUE	),
(	6	,	25	,	TRUE	),
(	6	,	26	,	TRUE	),
(	6	,	27	,	TRUE	),
(	6	,	28	,	TRUE	),
(	6	,	29	,	TRUE	),
(	6	,	30	,	TRUE	),
(	6	,	31	,	TRUE	),
(	7	,	11	,	TRUE	),
(	7	,	12	,	TRUE	),
(	7	,	13	,	TRUE	),
(	7	,	14	,	TRUE	),
(	7	,	15	,	TRUE	),
(	7	,	16	,	TRUE	),
(	7	,	17	,	TRUE	),
(	7	,	18	,	TRUE	),
(	7	,	19	,	TRUE	),
(	7	,	20	,	TRUE	),
(	7	,	21	,	TRUE	),
(	7	,	22	,	TRUE	),
(	8	,	23	,	TRUE	),
(	8	,	24	,	TRUE	),
(	8	,	25	,	TRUE	),
(	8	,	26	,	TRUE	),
(	8	,	27	,	FALSE	),
(	8	,	28	,	TRUE	),
(	8	,	29	,	TRUE	),
(	8	,	30	,	TRUE	),
(	8	,	31	,	TRUE	),
(	8	,	32	,	TRUE	),
(	8	,	33	,	TRUE	),
(	8	,	34	,	TRUE	),
(	8	,	35	,	TRUE	),
(	8	,	36	,	TRUE	),
(	8	,	37	,	TRUE	),
(	8	,	38	,	TRUE	),
(	8	,	39	,	TRUE	),
(	8	,	40	,	TRUE	),
(	9	,	41	,	TRUE	),
(	9	,	11	,	TRUE	),
(	9	,	12	,	TRUE	),
(	9	,	13	,	TRUE	),
(	9	,	14	,	TRUE	),
(	9	,	15	,	TRUE	),
(	9	,	16	,	TRUE	),
(	9	,	17	,	TRUE	),
(	9	,	18	,	TRUE	),
(	9	,	19	,	TRUE	),
(	9	,	20	,	TRUE	),
(	9	,	21	,	TRUE	),
(	9	,	22	,	TRUE	),
(	9	,	23	,	TRUE	),
(	9	,	24	,	TRUE	),
(	9	,	25	,	TRUE	),
(	9	,	26	,	TRUE	),
(	10	,	27	,	FALSE	),
(	10	,	28	,	TRUE	),
(	10	,	29	,	TRUE	),
(	10	,	30	,	TRUE	),
(	10	,	31	,	TRUE	),
(	10	,	32	,	TRUE	),
(	10	,	33	,	TRUE	),
(	10	,	34	,	TRUE	),
(	10	,	35	,	TRUE	),
(	10	,	36	,	TRUE	),
(	10	,	37	,	TRUE	),
(	10	,	38	,	TRUE	),
(	10	,	39	,	TRUE	),
(	10	,	40	,	TRUE	),
(	10	,	41	,	TRUE	);

select * from bookings;

-- call NewBooking(member_id, restaurant_id, start_time_slot,'duration')
-- call MemberIN(member_id) -- Prints booking_id
-- call OrderFood(Booking-id,MenuItem_id, quantity)
-- call MemberOUT(member_id)
-- Bramch ID in between 1 to 10. Cuisimes are inclued as below

CALL NewBooking(	1	,	1	,	3	,	2	, 'Website'	);
CALL NewBooking(	2	,	4	,	9	,	2	, 'Walk-in'	);
CALL NewBooking(	3	,	1	,	13	,	3	 , 'Phone Call'	);
CALL NewBooking(	4	,	4	,	12	,	1	, 'Website'	);
CALL NewBooking(	5	,	1	,	13	,	3	, 'Walk-in'	);
CALL NewBooking(	6	,	1	,	9	,	1	 , 'Phone Call'	);
CALL NewBooking(	7	,	4	,	6	,	1	, 'Website'	);
CALL NewBooking(	8	,	6	,	10	,	3	, 'Walk-in'	);
CALL NewBooking(	9	,	3	,	9	,	2	 , 'Phone Call'	);
CALL NewBooking(	10	,	3	,	3	,	3	, 'Website'	);
CALL NewBooking(	11	,	5	,	2	,	3	, 'Walk-in'	);
CALL NewBooking(	12	,	5	,	13	,	2	 , 'Phone Call'	);
CALL NewBooking(	13	,	3	,	8	,	3	, 'Website'	);
CALL NewBooking(	14	,	5	,	4	,	1	, 'Walk-in'	);
CALL NewBooking(	15	,	6	,	11	,	2	 , 'Phone Call'	);
CALL NewBooking(	16	,	2	,	4	,	1	, 'Website'	);
CALL NewBooking(	17	,	6	,	12	,	1	, 'Walk-in'	);
CALL NewBooking(	18	,	5	,	3	,	3	 , 'Phone Call'	);
CALL NewBooking(	19	,	3	,	1	,	1	, 'Website'	);
CALL NewBooking(	20	,	1	,	9	,	2	, 'Walk-in'	);
CALL NewBooking(	21	,	3	,	1	,	1	 , 'Phone Call'	);
CALL NewBooking(	22	,	5	,	12	,	2	, 'Website'	);
CALL NewBooking(	23	,	4	,	12	,	1	, 'Walk-in'	);
CALL NewBooking(	24	,	4	,	7	,	2	 , 'Phone Call'	);
CALL NewBooking(	25	,	4	,	2	,	3	, 'Website'	);
call NewBooking(35,3,4,5,'Walk-in');
call NewBooking(36,3,5,5,'Walk-in');
call NewBooking(37,3,6,5,'Walk-in');
call NewBooking(38,3,7,5,'Walk-in');
call NewBooking(39,3,8,5,'Walk-in');
call NewBooking(31,3,9,5,'Walk-in');
call NewBooking(32,3,4,5,'Walk-in');
call NewBooking(33,3,4,5,'Walk-in');
call NewBooking(34,3,4,5,'Walk-in');
call NewBooking(40,3,4,5,'Walk-in');
call NewBooking(30,3,4,5,'Walk-in');
call NewBooking(26,3,4,5,'Walk-in');
CALL NewBooking(	26	,	5	,	11	,	3	, 'Website'	);
CALL NewBooking(	27	,	3	,	3	,	3	, 'Walk-in'	);
CALL NewBooking(	28	,	4	,	1	,	3	 , 'Phone Call'	);
CALL NewBooking(	29	,	3	,	1	,	1	, 'Website'	);
CALL NewBooking(	30	,	1	,	10	,	1	, 'Walk-in'	);
CALL NewBooking(	31	,	3	,	12	,	1	 , 'Phone Call'	);
CALL NewBooking(	32	,	6	,	1	,	1	, 'Website'	);
CALL NewBooking(	33	,	1	,	3	,	3	, 'Walk-in'	);
CALL NewBooking(	34	,	1	,	6	,	2	 , 'Phone Call'	);
CALL NewBooking(	35	,	3	,	5	,	1	, 'Website'	);
CALL NewBooking(	36	,	4	,	10	,	3	, 'Walk-in'	);
CALL NewBooking(	41	,	2	,	7	,	1	, 'Website'	);
CALL NewBooking(	42	,	2	,	12	,	1	, 'Walk-in'	);
CALL NewBooking(	43	,	5	,	14	,	2	 , 'Phone Call'	);
CALL NewBooking(	44	,	2	,	11	,	1	, 'Website'	);
CALL NewBooking(	45	,	1	,	8	,	2	, 'Walk-in'	);
CALL NewBooking(	46	,	6	,	12	,	3	 , 'Phone Call'	);
CALL NewBooking(	47	,	5	,	7	,	2	, 'Website'	);
CALL NewBooking(	48	,	3	,	5	,	3	, 'Walk-in'	);
CALL NewBooking(	49	,	5	,	5	,	3	 , 'Phone Call'	);
CALL NewBooking(	50	,	4	,	11	,	2	, 'Website'	);

-- 46 records for booking completed

-- Check In 50 Members

Call MemberIn(	1	);
Call MemberIn(	2	);
Call MemberIn(	3	);
Call MemberIn(	4	);
Call MemberIn(	5	);
Call MemberIn(	6	);
Call MemberIn(	7	);
Call MemberIn(	8	);
Call MemberIn(	9	);
Call MemberIn(	10	);
Call MemberIn(	11	);
Call MemberIn(	12	);
Call MemberIn(	13	);
Call MemberIn(	14	);
Call MemberIn(	15	);
Call MemberIn(	16	);
Call MemberIn(	17	);
Call MemberIn(	18	);
Call MemberIn(	19	);
Call MemberIn(	20	);
Call MemberIn(	21	);
Call MemberIn(	22	);
Call MemberIn(	23	);
Call MemberIn(	24	);
Call MemberIn(	25	);
Call MemberIn(	26	);
Call MemberIn(	27	);
Call MemberIn(	28	);
Call MemberIn(	29	);
Call MemberIn(	30	);
Call MemberIn(	31	);
Call MemberIn(	32	);
Call MemberIn(	33	);
Call MemberIn(	34	);
Call MemberIn(	35	);
Call MemberIn(	36	);
Call MemberIn(	37	);
Call MemberIn(	38	);
Call MemberIn(	39	);
Call MemberIn(	40	);
Call MemberIn(	41	);
Call MemberIn(	42	);
Call MemberIn(	43	);
Call MemberIn(	44	);
Call MemberIn(	45	);
Call MemberIn(	46	);
Call MemberIn(	47	);
Call MemberIn(	48	);
Call MemberIn(	49	);
Call MemberIn(	50	);

CALL OrderFood(	1	,	29	,	2	);
CALL OrderFood(	2	,	21	,	1	);
CALL OrderFood(	3	,	16	,	1	);
CALL OrderFood(	4	,	17	,	3	);
CALL OrderFood(	5	,	28	,	1	);
CALL OrderFood(	6	,	12	,	3	);
CALL OrderFood(	7	,	24	,	3	);
CALL OrderFood(	8	,	20	,	1	);
CALL OrderFood(	9	,	10	,	3	);
CALL OrderFood(	10	,	20	,	2	);
CALL OrderFood(	11	,	10	,	1	);
CALL OrderFood(	12	,	16	,	2	);
CALL OrderFood(	13	,	15	,	3	);
CALL OrderFood(	14	,	16	,	1	);
CALL OrderFood(	15	,	18	,	3	);
CALL OrderFood(	16	,	27	,	2	);
CALL OrderFood(	17	,	26	,	2	);
CALL OrderFood(	18	,	18	,	2	);
CALL OrderFood(	19	,	16	,	1	);
CALL OrderFood(	20	,	21	,	3	);
CALL OrderFood(	21	,	13	,	3	);
CALL OrderFood(	22	,	25	,	1	);
CALL OrderFood(	23	,	25	,	1	);
CALL OrderFood(	24	,	16	,	3	);
CALL OrderFood(	25	,	21	,	1	);
CALL OrderFood(	26	,	24	,	3	);
CALL OrderFood(	27	,	26	,	2	);
CALL OrderFood(	28	,	20	,	1	);
CALL OrderFood(	29	,	28	,	2	);
CALL OrderFood(	30	,	21	,	1	);
CALL OrderFood(	31	,	19	,	2	);
CALL OrderFood(	32	,	23	,	3	);
CALL OrderFood(	33	,	24	,	3	);
CALL OrderFood(	34	,	10	,	2	);
CALL OrderFood(	35	,	15	,	2	);
CALL OrderFood(	36	,	12	,	1	);
CALL OrderFood(	37	,	28	,	1	);
CALL OrderFood(	38	,	13	,	2	);
CALL OrderFood(	39	,	26	,	3	);
CALL OrderFood(	40	,	16	,	3	);
CALL OrderFood(	41	,	21	,	2	);
CALL OrderFood(	42	,	13	,	3	);
CALL OrderFood(	43	,	28	,	1	);
CALL OrderFood(	44	,	21	,	2	);
CALL OrderFood(	45	,	21	,	1	);
CALL OrderFood(	46	,	19	,	1	);
CALL OrderFood(	47	,	23	,	1	);
CALL OrderFood(	48	,	30	,	1	);
CALL OrderFood(	49	,	30	,	1	);
CALL OrderFood(	50	,	30	,	1	);

CALL OrderFood(	1	,	12	,	2	);
CALL OrderFood(	2	,	19	,	1	);
CALL OrderFood(	3	,	11	,	1	);
CALL OrderFood(	4	,	25	,	2	);
CALL OrderFood(	5	,	10	,	1	);
CALL OrderFood(	6	,	29	,	3	);
CALL OrderFood(	7	,	28	,	3	);
CALL OrderFood(	8	,	28	,	2	);
CALL OrderFood(	9	,	19	,	2	);
CALL OrderFood(	10	,	27	,	1	);
CALL OrderFood(	11	,	28	,	2	);
CALL OrderFood(	12	,	25	,	2	);
CALL OrderFood(	13	,	26	,	1	);
CALL OrderFood(	14	,	28	,	2	);
CALL OrderFood(	15	,	10	,	1	);
CALL OrderFood(	16	,	23	,	2	);
CALL OrderFood(	17	,	29	,	1	);
CALL OrderFood(	18	,	25	,	2	);
CALL OrderFood(	19	,	10	,	3	);
CALL OrderFood(	20	,	17	,	3	);
CALL OrderFood(	21	,	26	,	2	);
CALL OrderFood(	22	,	22	,	3	);
CALL OrderFood(	23	,	22	,	3	);
CALL OrderFood(	24	,	30	,	1	);
CALL OrderFood(	25	,	16	,	1	);
CALL OrderFood(	26	,	30	,	3	);
CALL OrderFood(	27	,	15	,	1	);
CALL OrderFood(	28	,	29	,	1	);
CALL OrderFood(	29	,	22	,	1	);
CALL OrderFood(	30	,	23	,	1	);
CALL OrderFood(	31	,	30	,	3	);
CALL OrderFood(	32	,	16	,	3	);
CALL OrderFood(	33	,	15	,	2	);
CALL OrderFood(	34	,	14	,	3	);
CALL OrderFood(	35	,	25	,	1	);
CALL OrderFood(	36	,	13	,	3	);
CALL OrderFood(	37	,	15	,	2	);
CALL OrderFood(	38	,	13	,	2	);
CALL OrderFood(	39	,	17	,	3	);
CALL OrderFood(	40	,	28	,	3	);
CALL OrderFood(	41	,	19	,	3	);
CALL OrderFood(	42	,	27	,	2	);
CALL OrderFood(	43	,	22	,	1	);
CALL OrderFood(	44	,	10	,	3	);
CALL OrderFood(	45	,	23	,	1	);
CALL OrderFood(	46	,	25	,	1	);
CALL OrderFood(	47	,	27	,	1	);
CALL OrderFood(	48	,	30	,	2	);
CALL OrderFood(	49	,	12	,	1	);
CALL OrderFood(	50	,	15	,	1	);

Call MemberOut(	1	);
Call MemberOut(	2	);
Call MemberOut(	3	);
Call MemberOut(	4	);
Call MemberOut(	5	);
Call MemberOut(	6	);
Call MemberOut(	7	);
Call MemberOut(	8	);
Call MemberOut(	9	);
Call MemberOut(	10	);
Call MemberOut(	11	);
Call MemberOut(	12	);
Call MemberOut(	13	);
Call MemberOut(	14	);
Call MemberOut(	15	);
Call MemberOut(	16	);
Call MemberOut(	17	);
Call MemberOut(	18	);
Call MemberOut(	19	);
Call MemberOut(	20	);
Call MemberOut(	21	);
Call MemberOut(	22	);
Call MemberOut(	23	);
Call MemberOut(	24	);
Call MemberOut(	25	);
Call MemberOut(	26	);
Call MemberOut(	27	);
Call MemberOut(	28	);
Call MemberOut(	29	);
Call MemberOut(	30	);
Call MemberOut(	31	);
Call MemberOut(	32	);
Call MemberOut(	33	);
Call MemberOut(	34	);
Call MemberOut(	35	);
Call MemberOut(	36	);
Call MemberOut(	37	);
Call MemberOut(	38	);
Call MemberOut(	39	);
Call MemberOut(	40	);
Call MemberOut(	41	);
Call MemberOut(	42	);
Call MemberOut(	43	);
Call MemberOut(	44	);
Call MemberOut(	45	);
Call MemberOut(	46	);
Call MemberOut(	47	);
Call MemberOut(	48	);
Call MemberOut(	49	);
Call MemberOut(	50	);


CALL NewBooking(	3	,	3	,	14	,	2	, 'Website'	);
CALL NewBooking(	5	,	5	,	8	,	2	, 'Walk-in'	);
CALL NewBooking(	2	,	5	,	1	,	1	 , 'Phone Call'	);
CALL NewBooking(	4	,	1	,	9	,	3	, 'Website'	);
CALL NewBooking(	5	,	5	,	14	,	1	, 'Walk-in'	);
CALL NewBooking(	6	,	3	,	6	,	1	 , 'Phone Call'	);
CALL NewBooking(	32	,	3	,	3	,	3	, 'Website'	);
CALL NewBooking(	8	,	1	,	5	,	2	, 'Walk-in'	);
CALL NewBooking(	23	,	4	,	5	,	1	 , 'Phone Call'	);
CALL NewBooking(	10	,	4	,	13	,	2	, 'Website'	);
CALL NewBooking(	12	,	6	,	1	,	3	, 'Walk-in'	);

call CancelBooking(2);
call CancelBooking(47);
call CancelBooking(50);
call CancelBooking(51);
call CancelBooking(52);
call CancelBooking(53);
call CancelBooking(54);

call MemberIn(2);
call MemberIn(12);
call MemberIn(3);
call MemberIn(4);
call MemberIn(5);

CALL OrderFood(	48	,	26	,	1	);
CALL OrderFood(	48	,	25	,	2	);
CALL OrderFood(	49	,	19	,	3	);
CALL OrderFood(	50	,	29	,	3	);
CALL OrderFood(	49	,	16	,	1	);
CALL OrderFood(	49	,	10	,	2	);
CALL OrderFood(	50	,	21	,	1	);
CALL OrderFood(	50	,	11	,	3	);
CALL OrderFood(	55	,	21	,	1	);
CALL OrderFood(	55	,	11	,	3	);

call MemberOut(2);
call MemberOut(12);
call Memberout(3);
call MemberOut(4);
call MemberOut(5);

/*
-- Call NewBooking  to make new bookings
-- Call MemberIn to check in the customer
-- Call Orderfood for each checked in customer
-- Call MemberOut to check out the cusomter. The billing will be automaticaaly added
-- Call Cancel Order for few bookings

call NewBooking(35,3,4,5,'Walk-in');
call MemberIn(35);
call OrderFood(1,13,3);
call OrderFood(1,17,2); 
call MemberOut(35);

-- Following tables are automatically updated after calling procedure

call NewBooking(15,3,4,2,'Walk-in');
select * from Bookings;
select * from TableStatus;
select * from BookingStatus;

call MemberIn(15);
select * from BookingStatus;

call OrderFood(30,13,3);
select * from Orders;
select * from Billing;

call MemberOut(15);
select * from PastBookings;
select * from TableStatus;
select * from BookingStatus;

-- call CancelBooking(booking_id)
call CancelBooking(15);
select * from Bookings;
select * from TableStatus;
select * from BookingStatus;
*/

SHOW tables;
SHOW FUNCTION STATUS where Db='centralisedrestaurantreservationsystem';
SHOW PROCEDURE STATUS where Db='centralisedrestaurantreservationsystem';
SHOW TRIGGERS;

-- 1.Retrieve the names and email addresses of active members who made bookings through the website, along with the restaurant details where the booking was made.
SELECT 
    M.first_name, 
    M.last_name, 
    M.email, 
    BK.booking_method,
    B.restaurant_name, 
    B.location
FROM 
    Members M
    JOIN Bookings BK ON M.member_id = BK.member_id
    JOIN restaurants B ON BK.restaurant_id = B.restaurant_id
WHERE 
    M.member_status = 'Active' 
    AND BK.booking_method = 'Website';


-- 2. Query to calculate the average revenue per booking for each restaurant
SELECT 
    B.restaurant_id,
    R.restaurant_name,
    AVG(Billing.total_amount) AS avg_revenue_per_booking
FROM 
    Bookings B
    JOIN Billing ON B.booking_id = Billing.order_id
    JOIN restaurants R ON B.restaurant_id = R.restaurant_id
GROUP BY 
    B.restaurant_id, R.restaurant_name;


-- 3. Retrieve the top MenuItems with the highest total orders across all restaurantes.
SELECT C.MenuItem_name, COUNT(O.MenuItem_id) AS total_orders
FROM Orders O
JOIN MenuItems C ON O.MenuItem_id = C.MenuItem_id
GROUP BY O.MenuItem_id
ORDER BY total_orders DESC
LIMIT 15;

-- 4. Find the total number of bookings made by each member along with their cancellation status.
SELECT M.member_id, M.username, COUNT(B.booking_id) AS total_bookings,
       SUM(CASE WHEN BS.booking_status = 'cancelled' THEN 1 ELSE 0 END) AS total_cancellations,
       cancellation_penalty
FROM Members M
LEFT JOIN Bookings B ON M.member_id = B.member_id
LEFT JOIN BookingStatus BS ON B.booking_id = BS.booking_id
GROUP BY M.member_id;

-- 5. Retrieve the details of bookings made by members who have a cancellation penalty greater than $4.
SELECT 
    M.username, 
    B.booking_id, 
    B.start_time_slot, 
    B.booking_method,
    M.cancellation_penalty
FROM 
    Members M
    JOIN Bookings B ON M.member_id = B.member_id
WHERE 
    M.cancellation_penalty > 4;


-- 6. Find the restaurant with the highest average booking duration.
SELECT B.restaurant_name, AVG(BK.booking_duration) AS avg_duration
FROM Bookings BK
JOIN restaurants B ON BK.restaurant_id = B.restaurant_id
GROUP BY B.restaurant_name
ORDER BY avg_duration DESC
LIMIT 10;

-- 7. Retrieve the average total price after tax of bookings made by active members for each MenuItem, along with the MenuItem details.
SELECT C.MenuItem_name, AVG(PB.total_price_after_tax) AS avg_total_price_after_tax
FROM PastBookings PB
JOIN Bookings B ON PB.booking_id = B.booking_id
JOIN Members M ON B.member_id = M.member_id
JOIN Orders O ON B.booking_id = O.booking_id
JOIN MenuItems C ON O.MenuItem_id = C.MenuItem_id
WHERE M.member_status = 'Active'
GROUP BY C.MenuItem_name;

-- 8. Retrieve the top 3 restaurants with the highest ratio of completed bookings to total bookings.
SELECT B.restaurant_name, COUNT(CASE WHEN BS.booking_status = 'completed' THEN 1 END) / COUNT(*) AS completion_ratio
FROM restaurants B
JOIN Bookings BK ON B.restaurant_id = BK.restaurant_id
JOIN BookingStatus BS ON BK.booking_id = BS.booking_id
GROUP BY B.restaurant_name
ORDER BY completion_ratio DESC
LIMIT 3;

-- 9. Find the employee who has served the most number of bookings as a server in each restaurant.
SELECT B.restaurant_name,
       E.employee_name,
       COUNT(BK.booking_id) AS total_bookings_served
FROM Employees E
JOIN WorkShifts WS ON E.employee_id = WS.employee_id
JOIN Bookings BK ON WS.restaurant_id = BK.restaurant_id AND E.role = 'server'
JOIN restaurants B ON BK.restaurant_id = B.restaurant_id
GROUP BY B.restaurant_name, E.employee_name
ORDER BY B.restaurant_name, total_bookings_served DESC
LIMIT 10;

-- 10. Find the busiest time slots (start_time) across all restaurants based on the total number of bookings made.
SELECT T.start_time, COUNT(*) AS total_bookings
FROM Bookings BK
JOIN time_slots T ON BK.start_time_slot = T.slot_id
GROUP BY T.start_time
ORDER BY total_bookings DESC;












