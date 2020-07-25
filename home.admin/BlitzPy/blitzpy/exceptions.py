from datetime import datetime

TS_FORMAT = "%Y-%m-%dT%H:%M:%SZ"


class BlitzError(Exception):
    def __init__(self, short: str, details: dict = None, org: Exception = None):
        self.short: str = str(short)
        if details:
            self.details: dict = details
            self.details.update({'timestamp': datetime.utcnow().strftime(TS_FORMAT)})
        else:
            self.details = dict()
            self.details['timestamp'] = datetime.utcnow().strftime(TS_FORMAT)

        self.org: Exception = org
