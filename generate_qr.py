import qrcode

# Replace with your local server IP address
local_server_url = "https://b1b5-2401-4900-8898-f458-5150-5976-b58c-8b80.ngrok-free.app"

# Generate QR code
qr = qrcode.QRCode(
    version=1,
    error_correction=qrcode.constants.ERROR_CORRECT_L,
    box_size=10,
    border=4,
)
qr.add_data(local_server_url)
qr.make(fit=True)

# Create an image from the QR Code instance
img = qr.make_image(fill='black', back_color='white')
img.save("server_qr_code.png")

print(f"QR code generated for URL: {local_server_url}")
