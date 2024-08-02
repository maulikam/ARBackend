import qrcode

# Replace with your local server IP address
local_server_url = " https://95e3-2402-a00-405-ab3b-d9ba-ebfb-495c-9f26.ngrok-free.app"

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
