import network
import socket
import time
import ure
from machine import Pin, SPI

# Set up the Pico W as an access point
ap = network.WLAN(network.AP_IF)
ap.active(True)
ap.config(essid='Pico2W', password='password')

#============================================
# SPI0 on GP2=SCK, GP3=MOSI, GP0=MISO
#============================================
spi = SPI(
    0,
    baudrate=1_000_000,   # 1 MHz (tune as needed)
    polarity=0, phase=0,
    sck=Pin(2), mosi=Pin(3), miso=Pin(0)
)

# Chip‑select line (active low)
cs = Pin(1, Pin.OUT)
cs.value(1)  # deselect

# Wait for the access point to be active
while not ap.active():
    time.sleep(0.1)

print("Access Point active")
print("SSID:", ap.config('essid'))
print("IP address:", ap.ifconfig()[0])

# Define the HTML form
html = """<!DOCTYPE html>
<html>
<head>
    <title>Pico 2W Form</title>
    <meta name="viewport" content="width=device-width, initial-scale=1" />
</head>
<body>
    <h1>Encrypt or Decrypt</h1>
    <form method="POST">
      <p>Enter <span style="font-weight:bold">either</span>:</p>
      <ul>
        <li>A 10-digit phone number (e.g. 1234567890) to encrypt</li>
        <li>A 32-hex-digit string (e.g. CA4BCB48C849C94ECE4A52D2D2D2D2D2) to decrypt</li>
      </ul>
      <label>
        Data: 
        <input 
          type="text" 
          name="inputData" 
          placeholder="10 digits or 32 hex chars"
          pattern="(^\d{10}$)|(^[0-9A-Fa-f]{32}$)" 
          required />
      </label>
      <br/><br/>
      <button type="submit">Submit</button>
    </form>
</body>
</html>
"""

## HTML response after form submission
#def thank_you_page(phone_number, result_hex):
#    return f"""<!DOCTYPE html>
#<html>
#<head>
#    <title>Form Submitted</title>
#    <meta name="viewport" content="width=device-width, initial-scale=1" />
#</head>
#<body>
#    <h1>Thank You!</h1>
#    <p>Your phone number ({phone_number}) has been submitted.</p>
#    <p>This is the encrypted value: <strong>{result_hex}</strong></p>
#    <a href="/">Return to form</a>
# </body>
# </html>
# """

def thank_you_page(mode, input_data, result_hex):
    if mode == 'encrypt':
        title = "Encrypted!"
        body  = f"""
          <p>Your phone number <strong>{input_data}</strong><br>
          &rarr; ciphertext:</p>
          <pre>{result_hex}</pre>
        """
    else:
        # decrypt…
        raw = bytes.fromhex(result_hex)
        phone = raw.rstrip(b'\x00').decode('ascii', 'ignore')
        title = "Decrypted!"
        body  = f"""
          <p>Your ciphertext <strong>{input_data}</strong><br>
          &rarr; phone number:</p>
          <pre>{phone}</pre>
        """

    return f"""<!DOCTYPE html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{title}</title>
  </head>
  <body>
    <h1>{title}</h1>
    {body}
    <p><a href="/">Back</a></p>
  </body>
</html>
"""

# Set up a socket server
addr = socket.getaddrinfo('0.0.0.0', 80)[0][-1]
s = socket.socket()
s.bind(addr)
s.listen(1)

print('Listening on', addr)

# Function to parse form data from POST request
def parse_and_build_block(request):
    # 1) extract POST body
    lines = request.split('\r\n')
    for i, line in enumerate(lines):
        if line == '':
            raw_body = ''.join(lines[i+1:])
            break
    else:
        return None, None, None

    print("RAW BODY:", raw_body)   # keep this debug for a moment

    # 2) pull out inputData
    data = None
    for pair in raw_body.split('&'):
        k, sep, v = pair.partition('=')
        if k == 'inputData' and sep == '=':
            data = v
            break
    if not data:
        return None, None, None

    # 3) decide mode & build 16-byte block
    if len(data) == 10 and data.isdigit():
        mode  = 'encrypt'
        block = data.encode('ascii') + b'\x30' * 6

    elif len(data) == 32 and all(c in "0123456789abcdefABCDEF" for c in data):
        mode = 'decrypt'
        block = bytes(int(data[i:i+2], 16) for i in range(0, 32, 2))

    else:
        print("  → invalid data format:", data)
        return None, None, None

    print("  → parsed OK:", mode, "blocklen=", len(block))
    return data, block, mode

# Read 16 bytes back from the FPGA over SPI
def read_processed_from_spi():
    cs.value(0)                      # select
    data = spi.read(16)              # read 16 bytes from MISO
    cs.value(1)                      # deselect
    # Convert to a hex string, e.g. 'A1B2C3...'
    return ''.join(f'{b:02X}' for b in data)

#0 padding phone number to fit 128 bits
def pad_to_128bit(pn: str) -> bytes:
    b = pn.encode('ascii')
    return b + b'\x30' * (16 - len(b))


def send_phone_over_spi(pn: str):#pn used instead of phoneNumber only for this SPI function and converters
    block = pad_to_128bit(pn)    # 16 bytes
    print(f"Sending data over SPI: {block.hex()}")
    cs.value(0)                  # select the slave
    spi.write(block)             # send all 16 bytes
    cs.value(1)                  

# Main server loop
while True:
    cl = None
    try:
        cl, addr = s.accept()
        print('Client connected from', addr)
        request = cl.recv(1024).decode()
        print('REQUEST[:50]:', request.replace('\r\n','\\n')[:50])

        # only catch errors in handling this one request
        try:
            if request.startswith('POST'):
                data, block, mode = parse_and_build_block(request)
                print(f'  → parse → data={data!r}, mode={mode}, blocklen={len(block) if block else None}')
                if not block:
                    raise ValueError("parse_and_build_block returned no block")

                # SPI round-trip
                print(f"Sending data over through SPI: {block.hex()}")
                cs.value(0)
                spi.write(block)
                cs.value(1)
                cs.value(0)
                raw = spi.read(16)
                cs.value(1)

                result_hex = ''.join(f'{b:02X}' for b in raw)
                print('  → got raw from SPI:', raw, 'hex:', result_hex)

                # make a really minimal decrypt page so we can see it
                if mode == 'decrypt':
                    response = (
                        "HTTP/1.0 200 OK\r\n"
                        "Content-Type: text/html; charset=utf-8\r\n\r\n"
                        "<html><body>"
                        "<h1>DECRYPTED!</h1>"
                        f"<p>ciphertext: {data}</p>"
                        f"<p>plaintext hex: {result_hex}</p>"
                        '<p><a href="/">back</a></p>'
                        "</body></html>"
                    )
                else:
                    response = thank_you_page(mode, data, result_hex)

            else:
                # GET
                response = 'HTTP/1.0 200 OK\r\nContent-Type: text/html\r\n\r\n' + html

            # send it
            cl.send(response)

        except Exception as handler_e:
            # this will catch any bug in encrypt/decrypt/form logic
            print("!! Handler exception:", type(handler_e).__name__, repr(handler_e))
            # send a 500 so the browser doesn’t hang
            err_body = f"<h1>500 Server Error</h1><pre>{repr(handler_e)}</pre>"
            cl.send(
                "HTTP/1.0 500 Internal Server Error\r\n"
                "Content-Type: text/html; charset=utf-8\r\n\r\n"
                + err_body
            )

    except Exception as sock_e:
        print("** Socket error **", type(sock_e).__name__, repr(sock_e))
    finally:
        if cl:
            cl.close()
