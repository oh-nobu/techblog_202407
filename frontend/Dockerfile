# ベースイメージとしてPythonを使用
FROM python:3.9.12

# 作業ディレクトリを作成
WORKDIR /app

# 必要なパッケージをインストール
COPY requirements.txt .
RUN pip install -r requirements.txt

ENV PYTHONUNBUFFERED True

# アプリケーションのソースコードをコピー
COPY . .


# アプリを起動
CMD ["python", "main.py"]