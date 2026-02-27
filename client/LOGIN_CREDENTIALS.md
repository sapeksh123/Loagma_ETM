# Login Credentials

## Static Authentication Setup

### Admin Login
- **Phone Number**: `9999999999`
- **Role**: Admin
- **OTP**: `1234` (4-digit master OTP)

### Employee Login
- **Phone Number**: Any 10-digit number EXCEPT `9999999999`
- **Role**: Employee
- **OTP**: `1234` (4-digit master OTP)

## Examples

### Admin Access
1. Enter phone: `9999999999`
2. Click "Send OTP"
3. Enter OTP: `1234`
4. Redirects to Admin Dashboard

### Employee Access
1. Enter phone: `8888888888` (or any other 10-digit number)
2. Click "Send OTP"
3. Enter OTP: `1234`
4. Redirects to Employee Dashboard

## Features
- ✅ Logo loaded from `lib/assets/logo.png`
- ✅ Golden theme color: `0xFFceb56e`
- ✅ 4-digit OTP verification
- ✅ Role-based dashboard routing
- ✅ Static authentication (no backend required)
- ✅ Master OTP displayed on OTP screen for testing

## Notes
- The master OTP `1234` works for all phone numbers
- Only `9999999999` is recognized as admin
- All other valid 10-digit numbers are treated as employees
- No actual OTP is sent (static authentication for testing)
