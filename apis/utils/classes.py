# -*- coding: utf-8 -*-
import copy


class AttrDict(dict):
    def __init__(self, *args, **kwargs):
        super().__init__()
        self.update(*args, **kwargs)

    def __getattr__(self, attr):
        if attr in self.keys():
            return self[attr]
        else:
            raise AttributeError(
                f"'{self.__class__.__name__}' object has no attribute '{attr}'"
            )

    def __setattr__(self, attr, value):
        if attr in self.keys():
            self[attr] = value
        else:
            super().__setattr__(attr, value)

    def clone(self):
        return copy.deepcopy(self)
