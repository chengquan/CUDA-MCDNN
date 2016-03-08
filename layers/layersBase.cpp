#include"layersBase.h"

layersBase* Layers::getLayer(string name)
{
	if(_layersMaps.find(name) != _layersMaps.end())
	{
		return _layersMaps[name];
	}else
	{
		printf("layer: get layer %s is not exist\n",name.c_str());
		exit(0);
		return NULL;
	}
}


void Layers::storLayersName(string name)
{
	_layersName.push_back(name);
}


void Layers::storLayers(string name, layersBase* layer)
{
	if(_layersMaps.find(name) == _layersMaps.end())
	{
		_layersMaps[name] = layer;
		storLayersName(name);

		/*create a linked list*/
		if(_layersMaps.size() == 1)
		{
			_layersMaps[name]->prevLayer = NULL;
			_layersMaps[name]->_inputName = " ";
		}else
		{
			_layersMaps[name]->_inputName = _layersMaps[_layersName[_layersName.size() - 2]]->_name;
			_layersMaps[_layersName[_layersName.size() -2 ]]->nextLayer = _layersMaps[name];
			_layersMaps[name]->prevLayer = _layersMaps[_layersName[_layersName.size() - 2]];
		}

	}else
	{
		printf("layers: the layer %s have already in layersMap\n",name.c_str());
		exit(0);
	}

}



string Layers::getLayersName(int index)
{
	if(index >= _layersName.size())
	{
		printf("layers: the index %d has already out of layersName size\n", index);
		exit(0);
	}else
	{
		return _layersName[index];
	}
}
