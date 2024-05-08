from .fileRecord import FileRecord
from .peassRecord import PEASRecord
from .yamlGlobals import YAML_LOADED, DEFAULTS

class PEASLoaded:
    def __init__(self):
        to_search = YAML_LOADED["search"]
        self.peasrecords = []
        
        for record in to_search:
            record_value = record["value"]
            config = record_value.get("config", {})
            
            if "linpeas" in config.get("disable", "").lower():
                continue

            filerecords = [
                FileRecord(regex=filerecord["name"], **filerecord["value"])
                for filerecord in record_value["files"]
            ]
            
            self.peasrecords.append(
                PEASRecord(
                    name=record["name"],
                    auto_check=config.get("auto_check", DEFAULTS["auto_check"]),
                    exec=config.get("exec", DEFAULTS["exec"]),
                    filerecords=filerecords
                )
            )
