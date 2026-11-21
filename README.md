# Customized Staff Attendance Management Application

A cross-platform mobile attendance tracking system built with **Flutter, Dart, and Firebase** for multi-branch institutional deployment. Designed to eliminate proxy attendance using branch-specific QR code scanning and strict GPS geofencing.

## Key Features
- **Multi-Branch Geofencing:** Validates staff location within a strict **15-meter GPS radius** of the assigned branch before permitting check-in or check-out.
- **Branch-Specific QR Code Scanning:** Verifies physical branch presence via unique QR codes generated per office branch.
- **Automated Duplicate Prevention:** Prevents multiple check-ins or check-outs within the same shift cycle.
- **Role-Based Access Control:** Separate authentication flows and dashboards for **Staff** and **Administrators**.
- **Admin Dashboard & Reporting:** Enables administrators to manage staff records, configure branch GPS coordinates, and export attendance reports.

## Tech Stack
- **Frontend:** Flutter, Dart
- **Backend & Database:** Firebase Authentication, Cloud Firestore
- **Device Hardware & APIs:** Mobile Camera (QR Scanner), GPS / Location Services
- **IDE:** Android Studio

## Setup & Installation
1. **Clone the repository:**
   ```bash
   git clone https://github.com
   cd staff-attendance-flutter-app
   ```
2. **Install dependencies:**
   ```bash
   flutter pub get
   ```
3. **Configure Firebase:**
   - Create a new project in the [Firebase Console](https://google.com).
   - Enable **Email/Password Authentication** and **Cloud Firestore**.
   - Download your `google-services.json` (for Android) and place it inside `android/app/`.
4. **Run the application:**
   ```bash
   flutter run
   ```

## Author
**Promod Muthuram R**  
- LinkedIn: [://linkedin.com](https://www.://linkedin.com/)  
- Email: promodmuthuram29@gmail.com
