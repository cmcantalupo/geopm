from transformers import TrainerCallback, TrainingArguments, TrainerState, TrainerControl
from geopmpy import prof

class GeopmCallback(TrainerCallback):
    def __init__(self):
        all_names = ["init", "step"]
        self._name_id = dict()
        for nn in all_names:
            self._name_id[nn] = prof.region(nn, 1) # 1 == GEOPM_REGION_HINT_UNKNOWN
        self._begin("init")

    def _begin(self, name):
        prof.enter(self._name_id[name])

    def _end(self, name):
        prof.enter(self._name_id[name])

    def on_init_end(self, args: TrainingArguments, state: TrainerState, control: TrainerControl, **kwargs):
        self._end("init")

    def on_epoch_begin(self, args: TrainingArguments, state: TrainerState, control: TrainerControl, **kwargs):
        prof.epoch()

    def on_step_begin(self, args: TrainingArguments, state: TrainerState, control: TrainerControl, **kwargs):
        self._begin("step")

    def on_step_end(self, args: TrainingArguments, state: TrainerState, control: TrainerControl, **kwargs):
        self._end("step")
