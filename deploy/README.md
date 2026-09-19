# نشر موقع آيفونستا (iphonesta.com)

## التشغيل

```bash
bash build_compose.sh
```

يقرأ السكربت `../site/index.html`، يشفّره base64 بسطر واحد، ويولّد `docker-compose.yml`
مع حقن السلسلة في متغير البيئة `SITE_B64`، ثم يتحقق من سلامة الملف الناتج
(وجود `SITE_B64` غير فارغ، وصحة `ROUTE_JSON` كـ JSON عبر `jq` إن توفر).

بعد التوليد، على الخادم:

```bash
docker compose up -d
```

## البنية

- **site**: حاوية `nginx:1.27-alpine` تعيد فك تشفير `SITE_B64` إلى
  `/usr/share/nginx/html/index.html` عند الإقلاع وتخدم الصفحة على المنفذ 80 داخليًا.
  متصلة بشبكة خارجية اسمها `public-proxy` بالاسم المستعار `iphonesta-site`.
- **route-sync**: حاوية `curlimages/curl` تعمل بنمط `network_mode: container:reverse-proxy`
  (تشارك شبكة حاوية Caddy reverse-proxy). تراقب الـ Admin API الخاص بـ Caddy على
  `localhost:2019` كل 20 ثانية، وإن لم يوجد مسار باسم `iphonesta` تقوم بتثبيته عبر POST:
  إصغاء على `:443` للمضيفين `iphonesta.com` و `www.iphonesta.com` مع توجيه عكسي
  (reverse proxy) إلى `iphonesta-site:80`.

## المتطلبات المسبقة على الخادم

- شبكة Docker خارجية موجودة مسبقًا باسم `public-proxy` (`docker network create public-proxy`).
- حاوية Caddy باسم `reverse-proxy` مع تفعيل Admin API على المنفذ 2019.
- سجلات DNS للدومين `iphonesta.com` و `www.iphonesta.com` تشير إلى الخادم.
