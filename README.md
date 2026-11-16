# Application : NotiPlus

<p align="center">
  <b>NotiPlus</b><br>
  ระบบทดลองส่งการแจ้งเตือนจาก Web Dashboard ผ่าน API และ WebSocket ไปยังแอป Flutter
</p>

---

## About Application

NotiPlus เป็นโปรเจกต์สำหรับทดลองส่งหัวข้อ ข้อความ และรูปภาพจากหน้าเว็บไปยังแอปมือถือ โดยรวม Flutter Application, Web Dashboard และ Cloudflare Worker API ไว้ใน repository เดียวกัน

ฝั่งแอปเปิดการเชื่อมต่อ WebSocket เพื่อรอข้อความ เมื่อได้รับข้อมูล JSON จะเพิ่มรายการลงในหน้าการแจ้งเตือน และเรียก Local Notification ของอุปกรณ์ ส่วน Dashboard ใช้ HTTP API ส่งข้อความ และใช้ WebSocket อีกช่องทางเพื่อแสดงจำนวนอุปกรณ์ที่เชื่อมต่อ

โปรเจกต์นี้ใช้ WebSocket เป็นช่องทางรับข้อความ โดยไม่มีการเชื่อมต่อ FCM หรือ APNs สำหรับ Remote Push ในซอร์สโค้ดปัจจุบัน การรับข้อความใหม่จึงขึ้นกับการที่แอปยังมีการเชื่อมต่อกับเซิร์ฟเวอร์อยู่

---

## Features

### Flutter Application

- เชื่อมต่อ WebSocket เพื่อรับข้อมูลแจ้งเตือน
- มีตัวตั้งเวลาลองเชื่อมต่อใหม่หลังการเชื่อมต่อขาด
- แสดง Local Notification พร้อมหัวข้อและข้อความ
- ดาวน์โหลดรูปภาพจาก URL เพื่อแนบ Notification เมื่อดาวน์โหลดสำเร็จ
- แสดงรายการแจ้งเตือน เวลา และจำนวนรายการที่ยังไม่ได้เปิดดู
- เปิดหน้ารายละเอียดพร้อมข้อความและภาพประกอบ
- มีหน้าตัวอย่าง Home, Explore, Profile และหน้าสแกน QR Code

### Web Dashboard

- กรอกหัวข้อ ข้อความ และ URL รูปภาพที่ต้องการส่ง
- แสดงตัวอย่างรูปภาพก่อนส่งเมื่อ Browser โหลดภาพได้
- ส่งแจ้งเตือนทันทีผ่าน `POST /send`
- แสดงจำนวน Client ที่เชื่อมต่อแบบ Real-time
- เพิ่มหรือยกเลิกรายการตั้งเวลาส่งใน Browser
- เก็บรายการตั้งเวลาใน `localStorage`

### API & WebSocket Server

- ใช้ Cloudflare Worker รับ HTTP Request และ WebSocket Upgrade
- ส่งต่อการทำงานไปยัง Durable Object ชื่อ `NotificationHub`
- กระจายข้อความไปยัง Flutter Client ที่เชื่อมต่อทั้งหมด
- ส่งจำนวน Client ไปยัง Web Dashboard เมื่อมีการเชื่อมต่อหรือหลุด
- ตรวจรูปแบบ JSON และบังคับให้มี `title` กับ `body`

---

## System Overview

| ส่วนประกอบ | เทคโนโลยี | หน้าที่ |
|---|---|---|
| Mobile Application | Flutter / Dart | รับข้อความ แสดงรายการ และสร้าง Local Notification |
| Web Dashboard | HTML / CSS / JavaScript | กรอกข้อมูล ส่งข้อความ และจัดรายการตั้งเวลา |
| HTTP API | Cloudflare Workers | รับคำขอส่งข้อความและจัดการเส้นทาง |
| Notification Hub | Cloudflare Durable Objects | รวมการเชื่อมต่อ WebSocket ของแอปและ Dashboard |

ลำดับหลัก: Web Dashboard → HTTP API → NotificationHub → WebSocket → Flutter → Local Notification

---

## API Endpoints

| Endpoint | การใช้งาน |
|---|---|
| `GET /ws` | WebSocket Upgrade สำหรับ Flutter Client |
| `GET /ws-admin` | WebSocket Upgrade สำหรับรับจำนวนอุปกรณ์ที่เชื่อมต่อ |
| `POST /send` | ส่งข้อความไปยัง Flutter Client ทั้งหมดที่เชื่อมต่ออยู่ |

ตัวอย่างข้อมูลสำหรับ `POST /send`:

```json
{
  "title": "แจ้งเตือนจาก NotiPlus",
  "body": "ตัวอย่างข้อความสำหรับทดสอบระบบ",
  "imageUrl": "https://example.com/notification.jpg"
}
```

`imageUrl` เป็นข้อมูลเสริมและละได้ ตัวอย่าง URL ด้านบนเป็นเพียงรูปแบบข้อมูล ต้องเปลี่ยนเป็นลิงก์รูปภาพจริงที่อุปกรณ์เข้าถึงได้

เมื่อส่งสำเร็จ API จะตอบ `success`, `sent` และ `connected` โดย `sent` คือจำนวนครั้งที่ส่งข้อมูลผ่าน WebSocket สำเร็จ ไม่ใช่การยืนยันว่าผู้ใช้ได้รับหรือเปิดอ่านแล้ว

---

## Scheduling & Data Storage

การตั้งเวลาทำงานอยู่ใน JavaScript ของ Dashboard โดยตรวจรายการทุก 30 วินาทีและส่งคำขอเมื่อถึงเวลา จึงต้องเปิดหน้าเว็บไว้และให้ Browser ทำงานอยู่ ไม่ใช่ Scheduler ฝั่งเซิร์ฟเวอร์

ประวัติแจ้งเตือนฝั่ง Flutter เก็บในหน่วยความจำของแอปตามการทำงานปัจจุบัน ส่วนรายการตั้งเวลาเก็บใน Browser เดิมผ่าน `localStorage` และการเชื่อมต่อของ Hub เก็บเป็น WebSocket Session

---

## Project Structure

```text
notiplus/
├── lib/main.dart                 # UI, WebSocket และ Local Notification
├── pubspec.yaml
├── android/
├── ios/
└── cloudflare/
    ├── web/index.html            # Dashboard ส่งข้อความและตั้งเวลา
    └── worker/
        ├── src/index.js          # Worker และ NotificationHub
        ├── package.json
        └── wrangler.toml         # Binding และ Migration ของ Durable Object
```

---

## Technology Stack

- Flutter และ Dart
- Material Design 3
- `flutter_local_notifications`
- `web_socket_channel`
- `http` และ `path_provider`
- `mobile_scanner`
- HTML, CSS และ JavaScript
- Cloudflare Workers / Durable Objects
- WebSocket, HTTP และ JSON
- Browser localStorage

---

## Getting Started

### Flutter Application

เตรียม Flutter SDK ที่รองรับ Dart `^3.9.2` ตาม `pubspec.yaml` แล้วรัน:

```bash
git clone https://github.com/kittanai46/notiplus.git
cd notiplus
flutter pub get
flutter run
```

กำหนด `_wsUrl` ใน `lib/main.dart` ให้ตรงกับ Worker ที่ใช้งานและลงท้ายด้วย `/ws` จากนั้นอนุญาต Notification บนอุปกรณ์ ส่วนหน้าสแกน QR ต้องใช้สิทธิ์กล้อง

### Worker API

เข้าโฟลเดอร์ `cloudflare/worker` และติดตั้ง Dependency ด้วย `npm install` จากนั้นใช้ `npm run dev` สำหรับโหมดพัฒนา ตาม Script ที่กำหนดใน `package.json`

ไฟล์ `wrangler.toml` มี Binding ชื่อ `NOTIFICATION_HUB` ที่เชื่อมกับคลาส `NotificationHub` และ Migration ของ Durable Object สำหรับ Environment ที่จะนำไปใช้งาน

### Web Dashboard

เปิด `cloudflare/web/index.html` ผ่าน Static Web Server หรือ Static Hosting แล้วตั้งค่า `API_URL` และ `WS_ADMIN` ให้ชี้ไปยัง Worker เดียวกับแอป โดย URL ของ WebSocket สำหรับ Dashboard ลงท้ายด้วย `/ws-admin`

---

## Project Status

เป็นระบบทดลองแจ้งเตือนแบบ Broadcast ไปยัง Client ที่ออนไลน์อยู่ ยังไม่มีผู้รับรายบุคคล การยืนยันการเปิดอ่าน หรือการเก็บประวัติฝั่งเซิร์ฟเวอร์ และโค้ดปัจจุบันยังไม่มีขั้นตอนตรวจสิทธิ์ผู้ส่งใน `/send`

หน้า Home, Explore และ Profile ใช้ข้อมูลตัวอย่าง ส่วนการส่งแจ้งเตือนต้องมี Worker ที่เปิดใช้งานและเชื่อมต่อได้ คำอธิบายนี้อ้างอิงจากซอร์สโค้ด โดยยังไม่ได้ทดสอบส่งข้อความไปยังบริการที่ Deploy อยู่

---

## Repository Owner

[Kittanai Srikham](https://github.com/kittanai46)

