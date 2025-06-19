import logging
import time
from app import create_app
import os
import signal


app = create_app()


if __name__ == "__main__":
    time.sleep(5)
    print("app starting")
    logging.info("Flask app started")
    app.run(host="0.0.0.0", port=8000, use_reloader=False)









#
#   ngrok http 8000 --domain usually-whole-thrush.ngrok-free.app
#
#
#