#!/bin/bash

MODEL_DIR="../model/video_bagging"
rm ../model/video_bagging/ensemble.conf

for i in {1..2}; do
  sub_model_dir="${MODEL_DIR}/sub_model_${i}"
  mkdir -p $sub_model_dir

  # generate freq file
  python training_utils/sample_freq.py \
      --video_id_file="resources/train.video_id.vocab" \
      --output_freq_file="${sub_model_dir}/train.video_id.freq"

  # train N models with re-weighted samples
  CUDA_VISIBLE_DEVICES=0 python train.py \
    --train_dir="$sub_model_dir" \
    --train_data_pattern="/Youtube-8M/data/video/train/train*" \
    --frame_features=False \
    --feature_names="mean_rgb,mean_audio" \
    --feature_sizes="1024,128" \
    --model=DeepCombineChainModel \
    --moe_num_mixtures=4 \
    --deep_chain_relu_cells=256 \
    --deep_chain_layers=4 \
    --label_loss=MultiTaskCrossEntropyLoss \
    --multitask=True \
    --support_type="label,label,label,label" \
    --num_supports=18864 \
    --support_loss_percent=0.05 \
    --reweight=True \
    --sample_vocab_file="resources/train.video_id.vocab" \
    --sample_freq_file="${sub_model_dir}/train.video_id.freq" \
    --keep_checkpoint_every_n_hour=0.25 \
    --base_learning_rate=0.01 \
    --data_augmenter=NoiseAugmenter \
    --input_noise_level=0.2 \
    --num_readers=2 \
    --num_epochs=1 \
    --batch_size=1024

  # inference-pre-ensemble
  for part in ensemble_validate test; do
    CUDA_VISIBLE_DEVICES=0 python inference-pre-ensemble.py \
	    --output_dir="/Youtube-8M/model_predictions/${part}/video_deep_combine_chain_bagging/sub_model_$i" \
      --train_dir="${sub_model_dir}" \
	    --input_data_pattern="/Youtube-8M/data/video/${part}/*.tfrecord" \
	    --frame_features=False \
	    --feature_names="mean_rgb,mean_audio" \
	    --feature_sizes="1024,128" \
	    --batch_size=128 \
	    --file_size=4096
  done

  echo "video_deep_combine_chain_bagging/sub_model_$i" >> ../model/video_bagging/ensemble.conf

done

cd ../youtube-8m-ensemble
bash ensemble_scripts/eval-mean_model.sh video_bagging/ensemble_mean_model ../model/video_bagging/ensemble.conf
bash ensemble_scripts/infer-mean_model.sh video_bagging/ensemble_mean_model ../model/video_bagging/ensemble.conf